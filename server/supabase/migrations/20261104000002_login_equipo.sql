-- Login del equipo: con los datos del CRM cargados (bajo NDA), la API deja de ser pública.
-- Se entra con usuario y contraseña. Por dentro Supabase Auth necesita un mail: se usa <usuario>@equipo.motorespesados
-- (no es un mail real, nunca se le manda nada). Solo entran los usuarios que están en fiscal.usuario_permitido.
-- Para crear un usuario, en el SQL Editor:   select fiscal.crear_usuario('nombre', 'contraseña');
-- Para sacarle el acceso:                     delete from fiscal.usuario_permitido where email = 'nombre@equipo.motorespesados';

create table if not exists fiscal.usuario_permitido (
  email      text primary key check (email = lower(btrim(email)) and email like '%@%'),
  creado_en  timestamptz not null default now()
);
revoke all on fiscal.usuario_permitido from public;

-- Mail del usuario que hace el pedido (lo pone la API de Supabase en request.jwt.claims)
create or replace function public.es_del_equipo()
returns boolean language sql stable security definer set search_path = fiscal, pg_temp as $$
  select exists (
    select 1 from fiscal.usuario_permitido
    where email = lower(coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email', ''))
  )
$$;

-- Se corre antes de cada pedido a la API (db_pre_request). Fuera de la API (SQL Editor, pruebas) no hay claims y no corta nada.
create or replace function public.verificar_equipo()
returns void language plpgsql stable security definer set search_path = fiscal, pg_temp as $$
begin
  if nullif(current_setting('request.jwt.claims', true), '') is null then
    return;
  end if;
  if not public.es_del_equipo() then
    raise exception 'SIN_PERMISO'
      using errcode = '42501', detail = 'Para ver los datos tenés que entrar con un usuario del equipo.';
  end if;
end $$;

do $$
declare r record;
begin
  -- Ninguna función de la API queda abierta al rol anónimo
  for r in select p.oid::regprocedure as firma from pg_proc p
           where p.pronamespace = 'public'::regnamespace and p.prosecdef
             and p.proname not in ('es_del_equipo', 'verificar_equipo') loop
    execute format('revoke execute on function %s from public', r.firma);
    if exists (select 1 from pg_roles where rolname = 'anon') then
      execute format('revoke execute on function %s from anon', r.firma);
      execute format('grant execute on function %s to authenticated', r.firma);
    end if;
  end loop;

  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on function public.es_del_equipo(), public.verificar_equipo() from public;
    grant execute on function public.es_del_equipo(), public.verificar_equipo() to anon, authenticated;
  end if;

  -- Activar el control antes de cada pedido (solo existe en Supabase)
  if exists (select 1 from pg_roles where rolname = 'authenticator') then
    execute 'alter role authenticator set pgrst.db_pre_request to ''public.verificar_equipo''';
    perform pg_notify('pgrst', 'reload config');
  end if;
end $$;

-- Imágenes de facturas de compra: solo el equipo
drop policy if exists "comprobantes: subir" on storage.objects;
drop policy if exists "comprobantes: ver" on storage.objects;
create policy "comprobantes: subir" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'comprobantes' and public.es_del_equipo());
create policy "comprobantes: ver" on storage.objects
  for select to authenticated
  using (bucket_id = 'comprobantes' and public.es_del_equipo());

-- Crea (o cambia la contraseña de) un usuario del equipo y lo agrega a la lista. Solo se usa desde el SQL Editor.
create or replace function fiscal.crear_usuario(p_usuario text, p_contrasena text)
returns text language plpgsql security definer set search_path = fiscal, extensions, pg_temp as $$
declare
  v_usuario text := lower(btrim(p_usuario));
  v_email text;
  v_id uuid;
begin
  perform fiscal.req(v_usuario ~ '^[a-z0-9._-]{3,30}$', 'VALIDACION', 'El usuario va en minúsculas, sin espacios, de 3 a 30 letras o números.', 'usuario');
  perform fiscal.req(length(coalesce(p_contrasena, '')) >= 8, 'VALIDACION', 'La contraseña tiene que tener al menos 8 caracteres.', 'contrasena');
  v_email := v_usuario || '@equipo.motorespesados';
  select id into v_id from auth.users where email = v_email;
  if v_id is null then
    v_id := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                            confirmation_token, email_change, email_change_token_new, recovery_token)
    values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
            crypt(p_contrasena, gen_salt('bf')), now(),
            '{"provider":"email","providers":["email"]}', jsonb_build_object('usuario', v_usuario), now(), now(), '', '', '', '');
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), v_id, v_id::text, jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
            'email', now(), now(), now());
  else
    update auth.users set encrypted_password = crypt(p_contrasena, gen_salt('bf')), updated_at = now() where id = v_id;
  end if;
  insert into fiscal.usuario_permitido (email) values (v_email) on conflict do nothing;
  return v_usuario;
end $$;
revoke all on function fiscal.crear_usuario(text, text) from public;
