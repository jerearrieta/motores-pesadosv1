-- =====================================================================
-- Catálogos, cálculo fiscal y reglas que la base hace cumplir sola.
-- El cálculo vive acá (una sola versión): el front lo pide por RPC.
--   · Importes numeric(14,2). Redondeo: mitad hacia arriba (round() de
--     Postgres sobre numeric).
--   · Línea: precio unitario = round(lista × (100 − dto) ÷ 100, 4);
--            importe = round(cantidad × precio unitario, 2).
--   · IVA por alícuota sobre la suma de netos: round(base × % ÷ 100, 2).
--   · Precio final (factura B de mostrador): neto = round(total × 100 ÷ (100 + %), 2).
--   · Total = neto gravado + no gravado + exento + IVA + otros + percepciones.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Datos de catálogo
-- ---------------------------------------------------------------------
insert into fiscal.condicion_iva (codigo, descripcion, letra_venta) values
  (1, 'Responsable Inscripto', 'A'),
  (4, 'Sujeto Exento', 'B'),
  (5, 'Consumidor Final', 'B'),
  (6, 'Responsable Monotributo', 'A'),
  (7, 'Sujeto No Categorizado', null),
  (8, 'Proveedor del Exterior', null),
  (9, 'Cliente del Exterior', null),
  (10, 'IVA Liberado (Ley 19.640)', null),
  (13, 'Monotributista Social', null),
  (15, 'IVA No Alcanzado', null),
  (16, 'Monotributo Trabajador Independiente Promovido', null);

insert into fiscal.tipo_comprobante (codigo, descripcion, abreviatura, letra, clase, discrimina_iva, signo, venta, compra) values
  (1,  'Factura A',         'FA',  'A', 'factura',      true,  1,  true,  true),
  (2,  'Nota de Débito A',  'NDA', 'A', 'nota_debito',  true,  1,  true,  true),
  (3,  'Nota de Crédito A', 'NCA', 'A', 'nota_credito', true,  -1, true,  true),
  (6,  'Factura B',         'FB',  'B', 'factura',      false, 1,  true,  true),
  (7,  'Nota de Débito B',  'NDB', 'B', 'nota_debito',  false, 1,  true,  true),
  (8,  'Nota de Crédito B', 'NCB', 'B', 'nota_credito', false, -1, true,  true),
  (11, 'Factura C',         'FC',  'C', 'factura',      false, 1,  false, true),
  (12, 'Nota de Débito C',  'NDC', 'C', 'nota_debito',  false, 1,  false, true),
  (13, 'Nota de Crédito C', 'NCC', 'C', 'nota_credito', false, -1, false, true);

insert into fiscal.alicuota (codigo, descripcion, porcentaje, soportada) values
  (5, '21 %', 21.00, true),
  (4, '10,5 %', 10.50, true),
  (6, '27 %', 27.00, true),
  (3, '0 %', 0.00, true),
  (8, '5 %', 5.00, false),
  (9, '2,5 %', 2.50, false);

insert into fiscal.tipo_documento (codigo, descripcion) values
  (80, 'CUIT'), (86, 'CUIL'), (96, 'DNI'), (99, 'Consumidor Final (sin identificar)');

insert into fiscal.rol (id, descripcion) values
  ('administracion', 'Administración'),
  ('contador', 'Contador'),
  ('gerencia', 'Gerencia'),
  ('admin_tecnico', 'Administrador técnico'),
  ('lectura', 'Perfil de estudiante (solo lectura)');

insert into fiscal.permiso (accion, rol, texto)
select a.accion, r.rol, a.texto
from (values
  ('datos_fiscales', 'completar datos fiscales de clientes y proveedores', array['administracion', 'contador', 'admin_tecnico']),
  ('emitir_venta', 'crear borradores y emitir facturas de venta', array['administracion']),
  ('emitir_nota_venta', 'emitir notas de crédito y de débito', array['administracion']),
  ('cargar_compra', 'cargar y confirmar facturas de compra', array['administracion', 'contador']),
  ('anular_compra', 'anular facturas de compra', array['contador']),
  ('cerrar_periodo', 'cerrar períodos', array['contador']),
  ('ver_historial', 'ver el historial de cambios', array['contador', 'gerencia', 'admin_tecnico', 'lectura'])
) as a(accion, texto, roles)
cross join lateral unnest(a.roles) as r(rol);

-- ---------------------------------------------------------------------
-- Errores de negocio: el código va en el mensaje y el HTTP en el SQLSTATE
-- (PostgREST traduce PTxxx a ese status). El detalle es el texto para la persona.
-- ---------------------------------------------------------------------
create or replace function fiscal.error(p_codigo text, p_detalle text, p_campo text default null)
returns void language plpgsql as $$
declare
  v_http text := case
    when p_codigo in ('COMPROBANTE_INMUTABLE', 'PERIODO_CERRADO', 'ESTADO_INVALIDO', 'NUMERO_DUPLICADO', 'CLAVE_IDEMPOTENCIA_REUSADA') then '409'
    when p_codigo in ('PROHIBIDO', 'HISTORIAL_INMUTABLE') then '403'
    when p_codigo = 'NO_ENCONTRADO' then '404'
    else '422' end;
begin
  raise exception using errcode = 'PT' || v_http, message = p_codigo, detail = p_detalle, hint = coalesce(p_campo, '');
end $$;

create or replace function fiscal.req(p_condicion boolean, p_codigo text, p_detalle text, p_campo text default null)
returns void language plpgsql as $$
begin
  if p_condicion is not true then perform fiscal.error(p_codigo, p_detalle, p_campo); end if;
end $$;

-- ---------------------------------------------------------------------
-- Lectura de valores que manda el front (texto o número en el JSON)
-- ---------------------------------------------------------------------
create or replace function fiscal.leer_decimal(p_valor jsonb, p_decimales int, p_nombre text, p_permitir_negativo boolean default false)
returns numeric language plpgsql immutable as $$
declare v text;
begin
  if p_valor is null or p_valor = 'null'::jsonb then return 0; end if;
  v := btrim(p_valor #>> '{}');
  if v = '' then return 0; end if;
  if v !~ ('^' || case when p_permitir_negativo then '-?' else '' end || '\d+(\.\d{1,' || p_decimales || '})?$') then
    perform fiscal.error('VALIDACION', format('%s no es un número válido (hasta %s decimales): «%s».', p_nombre, p_decimales, v), p_nombre);
  end if;
  return v::numeric;
end $$;

create or replace function fiscal.importe(p_valor jsonb, p_nombre text)
returns numeric(14, 2) language sql immutable as $$
  select fiscal.leer_decimal(p_valor, 2, p_nombre)::numeric(14, 2)
$$;

-- ---------------------------------------------------------------------
-- Validaciones de identificación
-- ---------------------------------------------------------------------
create or replace function fiscal.cuit_valido(p_cuit text)
returns boolean language plpgsql immutable as $$
declare
  pesos int[] := array[5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  suma int := 0;
  resto int;
begin
  if p_cuit is null or p_cuit !~ '^\d{11}$' then return false; end if;
  for i in 1..10 loop suma := suma + pesos[i] * substr(p_cuit, i, 1)::int; end loop;
  resto := 11 - (suma % 11);
  if resto = 10 then return false; end if;
  return (case when resto = 11 then 0 else resto end) = substr(p_cuit, 11, 1)::int;
end $$;

create or replace function fiscal.documento_valido(p_tipo int, p_numero text)
returns boolean language sql immutable as $$
  select case
    when p_tipo in (80, 86) then fiscal.cuit_valido(p_numero)
    when p_tipo = 96 then coalesce(p_numero ~ '^\d{7,8}$', false)
    when p_tipo = 99 then p_numero = '0'
    else false end
$$;

alter table fiscal.contraparte add constraint documento_valido
  check (tipo_doc is null or fiscal.documento_valido(tipo_doc, numero_doc));
alter table fiscal.empresa add constraint cuit_empresa_valido check (fiscal.cuit_valido(cuit));

create or replace function fiscal.formatear_cuit(p text)
returns text language sql immutable as $$
  select case when p ~ '^\d{11}$' then substr(p, 1, 2) || '-' || substr(p, 3, 8) || '-' || substr(p, 11, 1) else coalesce(p, '') end
$$;

create or replace function fiscal.numero_comprobante(p_pv int, p_numero int)
returns text language sql immutable as $$
  select case when p_numero is null then 'sin número' else lpad(p_pv::text, 5, '0') || '-' || lpad(p_numero::text, 8, '0') end
$$;

-- ---------------------------------------------------------------------
-- Cálculo
-- ---------------------------------------------------------------------
create or replace function fiscal.calcular_iva(p_base numeric, p_porcentaje numeric)
returns numeric(14, 2) language sql immutable as $$
  select round(p_base * p_porcentaje / 100, 2)
$$;

create or replace function fiscal.porcentaje(p_alicuota int)
returns numeric language plpgsql stable as $$
declare v numeric;
begin
  select porcentaje into v from fiscal.alicuota where codigo = p_alicuota and soportada;
  if v is null then perform fiscal.error('VALIDACION', format('La alícuota %s no existe o todavía no está soportada.', coalesce(p_alicuota::text, '(vacía)')), 'alicuota_codigo'); end if;
  return v;
end $$;

-- Arma los importes del comprobante a partir del desglose por alícuota
create or replace function fiscal.importes_desde_desglose(p_desglose jsonb, p_extra jsonb default '{}')
returns jsonb language plpgsql immutable as $$
declare
  v_neto numeric(14, 2) := coalesce((select sum((d->>'base')::numeric) from jsonb_array_elements(p_desglose) d), 0);
  v_iva numeric(14, 2) := coalesce((select sum((d->>'iva')::numeric) from jsonb_array_elements(p_desglose) d), 0);
  v_no_gravado numeric(14, 2) := fiscal.importe(p_extra->'no_gravado', 'no_gravado');
  v_exento numeric(14, 2) := fiscal.importe(p_extra->'exento', 'exento');
  v_otros numeric(14, 2) := fiscal.importe(p_extra->'otros_tributos', 'otros_tributos');
  v_perc_iva numeric(14, 2) := fiscal.importe(p_extra->'percepcion_iva', 'percepcion_iva');
  v_perc_iibb numeric(14, 2) := fiscal.importe(p_extra->'percepcion_iibb', 'percepcion_iibb');
begin
  return jsonb_build_object(
    'neto_gravado', v_neto, 'no_gravado', v_no_gravado, 'exento', v_exento, 'iva', v_iva,
    'otros_tributos', v_otros, 'percepcion_iva', v_perc_iva, 'percepcion_iibb', v_perc_iibb,
    'total', v_neto + v_no_gravado + v_exento + v_iva + v_otros + v_perc_iva + v_perc_iibb);
end $$;

-- Desglose por alícuota a partir de pares {alicuota_codigo, base}: agrupa y calcula el IVA
create or replace function fiscal.desglosar(p_bases jsonb)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('alicuota_codigo', g.codigo, 'porcentaje', g.porcentaje, 'base', g.base,
                                               'iva', fiscal.calcular_iva(g.base, g.porcentaje)) order by g.porcentaje desc), '[]'::jsonb)
  from (
    select a.codigo, a.porcentaje, sum((b->>'base')::numeric)::numeric(14, 2) as base
    from jsonb_array_elements(p_bases) b
    join fiscal.alicuota a on a.codigo = (b->>'alicuota_codigo')::int
    group by a.codigo, a.porcentaje
  ) g
$$;

-- Factura de venta: líneas → ítems, desglose e importes. No escribe nada.
create or replace function fiscal.calcular_venta(p_lineas jsonb, p_modo text default 'neto')
returns jsonb language plpgsql stable as $$
declare
  l jsonb;
  v_items jsonb := '[]';
  v_bases jsonb := '[]';
  v_pct numeric;
  v_cant numeric; v_lista numeric; v_dto numeric; v_unit numeric(16, 4); v_neto numeric(14, 2); v_total numeric(14, 2);
  v_orden int := 0;
  v_desglose jsonb;
begin
  perform fiscal.req(jsonb_typeof(p_lineas) = 'array' and jsonb_array_length(p_lineas) > 0, 'VALIDACION', 'Agregá al menos una línea.', 'lineas');
  perform fiscal.req(p_modo in ('neto', 'precio_final'), 'VALIDACION', 'Modo de carga inválido.', 'modo');
  if p_modo = 'precio_final' then
    perform fiscal.req(jsonb_array_length(p_lineas) = 1, 'VALIDACION', 'Con precio final (IVA incluido) se carga una sola línea.', 'lineas');
  end if;
  for l in select * from jsonb_array_elements(p_lineas) loop
    v_orden := v_orden + 1;
    perform fiscal.req(coalesce(btrim(l->>'descripcion'), '') <> '', 'VALIDACION', format('La línea %s necesita una descripción.', v_orden), 'descripcion');
    v_pct := fiscal.porcentaje((l->>'alicuota_codigo')::int);
    if p_modo = 'precio_final' then
      v_total := fiscal.importe(l->'total', 'total');
      perform fiscal.req(v_total > 0, 'VALIDACION', 'Escribí el precio final (con IVA incluido).', 'total');
      v_neto := round(v_total * 100 / (100 + v_pct), 2);
      v_cant := 1; v_lista := v_neto; v_dto := 0; v_unit := v_neto;
    else
      v_cant := fiscal.leer_decimal(l->'cantidad', 4, 'cantidad');
      v_lista := fiscal.leer_decimal(l->'precio', 4, 'precio');
      v_dto := fiscal.leer_decimal(l->'descuento', 2, 'descuento');
      perform fiscal.req(v_cant > 0, 'VALIDACION', format('La cantidad de la línea %s tiene que ser mayor que cero.', v_orden), 'cantidad');
      perform fiscal.req(v_dto between 0 and 100, 'VALIDACION', 'El descuento va de 0 a 100.', 'descuento');
      v_unit := round(v_lista * (100 - v_dto) / 100, 4);
      v_neto := round(v_cant * v_unit, 2);
    end if;
    v_items := v_items || jsonb_build_object(
      'orden', v_orden, 'codigo', coalesce(btrim(l->>'codigo'), ''), 'descripcion', btrim(l->>'descripcion'),
      'cantidad', v_cant, 'precio_lista', v_lista, 'descuento', v_dto, 'precio_unitario', v_unit,
      'alicuota_codigo', (l->>'alicuota_codigo')::int, 'importe_neto', v_neto);
    v_bases := v_bases || jsonb_build_object('alicuota_codigo', (l->>'alicuota_codigo')::int, 'base', v_neto);
  end loop;
  v_desglose := fiscal.desglosar(v_bases);
  if p_modo = 'precio_final' then
    -- el IVA es la diferencia: el total impreso tiene que ser exactamente el que se cobró
    v_desglose := jsonb_build_array(jsonb_set(v_desglose->0, '{iva}', to_jsonb((v_total - v_neto)::numeric(14, 2))));
  end if;
  return jsonb_build_object('items', v_items, 'desglose', v_desglose, 'importes', fiscal.importes_desde_desglose(v_desglose));
end $$;

-- Factura de compra: lo que dice el papel del proveedor. B y C no discriminan IVA.
create or replace function fiscal.calcular_compra(p_tipo int, p_desglose jsonb, p_extra jsonb default '{}')
returns jsonb language plpgsql stable as $$
declare
  t fiscal.tipo_comprobante;
  d jsonb;
  v_bases jsonb := '[]';
  v_base numeric(14, 2);
  v_desglose jsonb;
  v_importes jsonb;
begin
  select * into t from fiscal.tipo_comprobante where codigo = p_tipo and compra;
  perform fiscal.req(t.codigo is not null, 'TIPO_INVALIDO', 'Elegí un tipo de comprobante de compra válido.', 'tipo');
  for d in select * from jsonb_array_elements(coalesce(p_desglose, '[]')) loop
    v_base := fiscal.importe(d->'base', 'base');
    continue when v_base = 0;
    perform fiscal.req(t.discrimina_iva, 'IVA_SIN_CREDITO',
      format('Una %s no discrimina IVA computable: se carga con IVA en cero y todo el importe como no gravado.', t.descripcion), 'tipo');
    perform fiscal.porcentaje((d->>'alicuota_codigo')::int);
    v_bases := v_bases || jsonb_build_object('alicuota_codigo', (d->>'alicuota_codigo')::int, 'base', v_base);
  end loop;
  v_desglose := fiscal.desglosar(v_bases);
  v_importes := fiscal.importes_desde_desglose(v_desglose, coalesce(p_extra, '{}'));
  return jsonb_build_object('desglose', v_desglose, 'importes', v_importes);
end $$;

-- ---------------------------------------------------------------------
-- Inmutabilidad: lo emitido o confirmado no se edita ni se borra
-- ---------------------------------------------------------------------
create or replace function fiscal.t_comprobante_inmutable()
returns trigger language plpgsql as $$
declare
  campos_anulacion text[] := array['estado', 'anulado_en', 'anulado_rol', 'motivo_anulacion'];
  campos_cae text[] := array['estado', 'cae', 'vto_cae'];
begin
  if tg_op = 'DELETE' then
    if old.estado <> 'borrador' then
      perform fiscal.error('COMPROBANTE_INMUTABLE', 'Un comprobante emitido o confirmado no se borra. Se corrige con una nota de crédito o de débito, o se anula.');
    end if;
    return old;
  end if;
  if old.estado = 'borrador' then return new; end if;
  -- compra confirmada → anulada, solo cambian los datos de la anulación
  if old.estado = 'confirmada' and new.estado = 'anulada'
     and (to_jsonb(new) - campos_anulacion) = (to_jsonb(old) - campos_anulacion) then
    return new;
  end if;
  -- venta emitida sin CAE → autorizada, solo se agrega el CAE
  if old.estado = 'emitido_sin_cae' and new.estado = 'autorizado'
     and (to_jsonb(new) - campos_cae) = (to_jsonb(old) - campos_cae) then
    return new;
  end if;
  perform fiscal.error('COMPROBANTE_INMUTABLE', 'El comprobante ya fue emitido o confirmado y no se puede editar. Se corrige con una nota de crédito o de débito.');
  return null;
end $$;

create trigger t_inmutable before update or delete on fiscal.comprobante
  for each row execute function fiscal.t_comprobante_inmutable();

-- Las líneas y el desglose solo cambian mientras el comprobante es borrador
create or replace function fiscal.t_detalle_inmutable()
returns trigger language plpgsql as $$
declare v_estado text;
begin
  select estado into v_estado from fiscal.comprobante where id = coalesce(new.comprobante_id, old.comprobante_id);
  if v_estado is not null and v_estado <> 'borrador' then
    perform fiscal.error('COMPROBANTE_INMUTABLE', 'El detalle de un comprobante emitido o confirmado no se puede modificar.');
  end if;
  return coalesce(new, old);
end $$;

create trigger t_inmutable before insert or update or delete on fiscal.comprobante_linea
  for each row execute function fiscal.t_detalle_inmutable();
create trigger t_inmutable before insert or update or delete on fiscal.comprobante_iva
  for each row execute function fiscal.t_detalle_inmutable();

create or replace function fiscal.t_historial_inmutable()
returns trigger language plpgsql as $$
begin
  perform fiscal.error('HISTORIAL_INMUTABLE', 'El historial es de solo altas: no se edita ni se borra.');
  return null;
end $$;

create trigger t_inmutable before update or delete on fiscal.historial
  for each row execute function fiscal.t_historial_inmutable();

-- ---------------------------------------------------------------------
-- Ayudas para las funciones de la API
-- ---------------------------------------------------------------------
create or replace function fiscal.exigir(p_rol text, p_accion text)
returns void language plpgsql stable as $$
declare v_texto text; v_roles text;
begin
  perform fiscal.req(exists (select 1 from fiscal.rol where id = p_rol), 'PROHIBIDO', 'Elegí un rol válido.');
  if not exists (select 1 from fiscal.permiso where accion = p_accion and rol = p_rol) then
    select min(p.texto), string_agg(r.descripcion, ', ' order by r.descripcion) into v_texto, v_roles
    from fiscal.permiso p join fiscal.rol r on r.id = p.rol where p.accion = p_accion;
    perform fiscal.error('PROHIBIDO', format('Tu rol (%s) no puede %s. Lo hacen: %s.',
      (select descripcion from fiscal.rol where id = p_rol), v_texto, v_roles));
  end if;
end $$;

create or replace function fiscal.registrar(p_rol text, p_empresa text, p_accion text, p_entidad text, p_ref text, p_detalle text)
returns void language sql as $$
  insert into fiscal.historial (rol, empresa_id, accion, entidad, ref, detalle) values (p_rol, p_empresa, p_accion, p_entidad, coalesce(p_ref, ''), coalesce(p_detalle, ''))
$$;

create or replace function fiscal.estado_periodo(p_empresa text, p_periodo text)
returns text language sql stable as $$
  select coalesce((select estado from fiscal.periodo_iva where empresa_id = p_empresa and periodo = p_periodo), 'abierto')
$$;

create or replace function fiscal.exigir_periodo_abierto(p_empresa text, p_periodo text, p_que text)
returns void language plpgsql stable as $$
begin
  perform fiscal.req(fiscal.estado_periodo(p_empresa, p_periodo) = 'abierto', 'PERIODO_CERRADO',
    format('El período %s está cerrado: no se puede %s.', p_periodo, p_que), 'fecha');
end $$;

create or replace function fiscal.siguiente_numero(p_empresa text, p_pv int, p_tipo int)
returns int language plpgsql as $$
declare v int;
begin
  insert into fiscal.numerador (empresa_id, punto_venta, tipo) values (p_empresa, p_pv, p_tipo) on conflict do nothing;
  select ultimo + 1 into v from fiscal.numerador where empresa_id = p_empresa and punto_venta = p_pv and tipo = p_tipo for update;
  update fiscal.numerador set ultimo = v where empresa_id = p_empresa and punto_venta = p_pv and tipo = p_tipo;
  return v;
end $$;

create or replace function fiscal.etiqueta(c fiscal.comprobante)
returns text language sql stable as $$
  select t.descripcion || ' ' || fiscal.numero_comprobante(c.punto_venta, c.numero) from fiscal.tipo_comprobante t where t.codigo = c.tipo
$$;

create or replace function fiscal.importe_texto(p numeric)
returns text language sql immutable as $$
  select '$ ' || replace(replace(replace(to_char(p, 'FM999G999G999G990D00'), ',', '#'), '.', ','), '#', '.')
$$;

-- Escribe ítems y desglose de un borrador (borra lo anterior)
create or replace function fiscal.guardar_detalle(p_id uuid, p_items jsonb, p_desglose jsonb)
returns void language plpgsql as $$
begin
  delete from fiscal.comprobante_linea where comprobante_id = p_id;
  delete from fiscal.comprobante_iva where comprobante_id = p_id;
  insert into fiscal.comprobante_linea (comprobante_id, orden, codigo, descripcion, cantidad, precio_lista, descuento, precio_unitario, alicuota_codigo, importe_neto)
  select p_id, (i->>'orden')::int, i->>'codigo', i->>'descripcion', (i->>'cantidad')::numeric, (i->>'precio_lista')::numeric, (i->>'descuento')::numeric,
         (i->>'precio_unitario')::numeric, (i->>'alicuota_codigo')::int, (i->>'importe_neto')::numeric
  from jsonb_array_elements(coalesce(p_items, '[]')) i;
  insert into fiscal.comprobante_iva (comprobante_id, alicuota_codigo, base, iva)
  select p_id, (d->>'alicuota_codigo')::int, (d->>'base')::numeric, (d->>'iva')::numeric
  from jsonb_array_elements(coalesce(p_desglose, '[]')) d;
end $$;

-- Idempotencia: misma clave + mismos datos = misma respuesta, sin volver a emitir
create or replace function fiscal.idem_buscar(p_clave uuid, p_funcion text, p_datos jsonb)
returns jsonb language plpgsql as $$
declare r fiscal.idempotencia;
begin
  if p_clave is null then return null; end if;
  select * into r from fiscal.idempotencia where clave = p_clave;
  if r.clave is null then return null; end if;
  perform fiscal.req(r.funcion = p_funcion and r.request_hash = md5(p_datos::text), 'CLAVE_IDEMPOTENCIA_REUSADA',
    'Esa clave de reintento ya se usó con otros datos.');
  return r.respuesta;
end $$;

create or replace function fiscal.idem_guardar(p_clave uuid, p_funcion text, p_datos jsonb, p_respuesta jsonb)
returns jsonb language plpgsql as $$
begin
  if p_clave is not null then
    insert into fiscal.idempotencia (clave, funcion, request_hash, respuesta) values (p_clave, p_funcion, md5(p_datos::text), p_respuesta);
  end if;
  return p_respuesta;
end $$;
