-- =====================================================================
-- Conciliación con ARCA («Mis Comprobantes»), US-064 y US-111.
-- Lleva al servidor parsearCsv, importeFlexible, leerMisComprobantes,
-- conciliar, registrarConciliacion, importarDesdeArca,
-- confirmarImportadas y archivoEjemploArca del Simulador Libro de IVA
-- (nucleo.js, sección 12). Todos los datos de ejemplo son inventados:
-- los códigos de autorización del archivo de ejemplo son «FICTICIO-…».
-- =====================================================================

-- De dónde viene el comprobante y el código de autorización que informa ARCA
-- (en el archivo de ejemplo no tiene forma de CAE, por eso va aparte del CAE).
alter table fiscal.comprobante
  add column origen text not null default 'manual' check (origen in ('manual', 'arca')),
  add column codigo_autorizacion text not null default '';

-- Última conciliación de cada empresa, período y archivo (para el cierre y para IVA Simple)
create table fiscal.conciliacion_arca (
  empresa_id    text not null references fiscal.empresa (id),
  periodo       text not null check (periodo ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  tipo_archivo  text not null check (tipo_archivo in ('recibidos', 'emitidos')),
  archivo       text not null default '',
  resumen       jsonb not null,
  diferencias   jsonb not null default '[]',
  tot_arca      jsonb not null default '{}',
  tot_sistema   jsonb not null default '{}',
  rol           text not null,
  cuando        timestamptz not null default now(),
  primary key (empresa_id, periodo, tipo_archivo)
);
revoke all on fiscal.conciliacion_arca from public;

insert into fiscal.permiso (accion, rol, texto) values
  ('importar_arca', 'administracion', 'importar comprobantes desde ARCA'),
  ('importar_arca', 'contador', 'importar comprobantes desde ARCA');

-- ---------------------------------------------------------------------
-- Lectura del archivo
-- ---------------------------------------------------------------------
create or replace function fiscal.sin_tildes(p text)
returns text language sql immutable as $$
  select translate(coalesce(p, ''), 'áéíóúàèìòùäëïöüâêîôûñÁÉÍÓÚÀÈÌÒÙÄËÏÖÜÂÊÎÔÛÑ', 'aeiouaeiouaeiouaeiounAEIOUAEIOUAEIOUAEIOUN')
$$;

-- Título de columna normalizado: minúsculas, sin tildes ni puntos, espacios simples
create or replace function fiscal.norm_cab(p text)
returns text language sql immutable as $$
  select btrim(regexp_replace(replace(replace(lower(fiscal.sin_tildes(p)), '.', ''), '_', ' '), '\s+', ' ', 'g'))
$$;

-- CSV con punto y coma, coma o tabulador (el que más aparezca en la primera línea), con comillas
-- y con o sin la marca de orden de bytes. Devuelve las filas no vacías como listas de textos.
create or replace function fiscal.parsear_csv(p_texto text)
returns jsonb language plpgsql immutable as $$
declare
  t text := coalesce(p_texto, '');
  primera text;
  sep text;
  c text[];
  n int;
  i int := 1;
  ch text;
  campo text := '';
  fila text[] := '{}';
  filas jsonb := '[]';
  comillas boolean := false;
begin
  if left(t, 1) = chr(65279) then t := substr(t, 2); end if;
  select l into primera from regexp_split_to_table(t, '\r?\n') with ordinality x(l, o) where btrim(l) <> '' order by o limit 1;
  primera := coalesce(primera, '');
  select s into sep from (values (1, ';'), (2, ','), (3, E'\t')) v(o, s)
  order by length(primera) - length(replace(primera, s, '')) desc, o limit 1;
  c := regexp_split_to_array(t, '');
  n := coalesce(array_length(c, 1), 0);
  if t = '' then n := 0; end if;
  while i <= n loop
    ch := c[i];
    if comillas then
      if ch = '"' then
        if i < n and c[i + 1] = '"' then campo := campo || '"'; i := i + 1; else comillas := false; end if;
      else campo := campo || ch; end if;
    elsif ch = '"' then comillas := true;
    elsif ch = sep then fila := fila || campo; campo := '';
    elsif ch = E'\n' or ch = E'\r' then
      if ch = E'\r' and i < n and c[i + 1] = E'\n' then i := i + 1; end if;
      fila := fila || campo;
      filas := filas || jsonb_build_array(to_jsonb(fila));
      fila := '{}'; campo := '';
    else campo := campo || ch; end if;
    i := i + 1;
  end loop;
  if campo <> '' or cardinality(fila) > 0 then
    fila := fila || campo;
    filas := filas || jsonb_build_array(to_jsonb(fila));
  end if;
  return coalesce((select jsonb_agg(f order by o) from jsonb_array_elements(filas) with ordinality x(f, o)
                   where exists (select 1 from jsonb_array_elements_text(f) v where btrim(v) <> '')), '[]');
end $$;

-- Importe escrito de cualquier forma («1.234,56», «1,234.56», «-36300», «(150,00)», «$ 1.500») a número
-- con dos decimales (el tercero redondea hacia arriba). Null si no se entiende.
create or replace function fiscal.importe_flexible(p_txt text)
returns numeric language plpgsql immutable as $$
declare
  s text;
  neg boolean := false;
  ip int; ic int; d int;
  ent text; dec text := '';
  partes text[];
  d3 text;
  cent numeric;
begin
  if p_txt is null then return 0; end if;
  s := regexp_replace(regexp_replace(btrim(p_txt), '\s', '', 'g'), '\$|ARS|USD|U\$S', '', 'gi');
  if s = '' or s = '-' then return 0; end if;
  if left(s, 1) = '(' and right(s, 1) = ')' then neg := true; s := substr(s, 2, length(s) - 2); end if;
  if left(s, 1) = '-' then neg := true; s := substr(s, 2); end if;
  ip := case when position('.' in s) > 0 then length(s) - position('.' in reverse(s)) + 1 else 0 end;
  ic := case when position(',' in s) > 0 then length(s) - position(',' in reverse(s)) + 1 else 0 end;
  if ip > 0 and ic > 0 then
    d := greatest(ip, ic);
    ent := regexp_replace(substr(s, 1, d - 1), '[.,]', '', 'g');
    dec := substr(s, d + 1);
  elsif ip > 0 or ic > 0 then
    partes := string_to_array(s, case when ic > 0 then ',' else '.' end);
    if array_length(partes, 1) = 2 and length(partes[2]) <> 3 then ent := partes[1]; dec := partes[2];
    else ent := array_to_string(partes, ''); end if;
  else
    ent := s;
  end if;
  ent := coalesce(nullif(ent, ''), '0');
  if ent !~ '^\d+$' or dec !~ '^\d*$' then return null; end if;
  d3 := substr(dec || '000', 1, 3);
  cent := ent::numeric * 100 + substr(d3, 1, 2)::numeric;
  if substr(d3, 3, 1)::int >= 5 then cent := cent + 1; end if;
  return round((case when neg then -cent else cent end) / 100, 2);
end $$;

create or replace function fiscal.cotizacion_flexible(p_txt text)
returns numeric language plpgsql immutable as $$
declare s text := regexp_replace(btrim(coalesce(p_txt, '')), '\s', '', 'g'); ip int; ic int; d int; m text[];
begin
  if s = '' then return 1; end if;
  ip := case when position('.' in s) > 0 then length(s) - position('.' in reverse(s)) + 1 else 0 end;
  ic := case when position(',' in s) > 0 then length(s) - position(',' in reverse(s)) + 1 else 0 end;
  if ip > 0 and ic > 0 then d := greatest(ip, ic); s := regexp_replace(substr(s, 1, d - 1), '[.,]', '', 'g') || '.' || substr(s, d + 1);
  elsif ic > 0 then s := replace(s, ',', '.'); end if;
  m := regexp_match(s, '^(\d+)(?:\.(\d+))?$');
  if m is null then return 1; end if;
  return (m[1] || coalesce('.' || left(m[2], 6), ''))::numeric;
end $$;

-- «dd/mm/aaaa», «dd-mm-aa», «aaaa-mm-dd» o número de serie de Excel
create or replace function fiscal.fecha_flexible(p_txt text)
returns date language plpgsql immutable as $$
declare s text := btrim(coalesce(p_txt, '')); m text[];
begin
  m := regexp_match(s, '^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})$');
  if m is not null then
    return make_date((case when length(m[3]) = 2 then '20' || m[3] else m[3] end)::int, m[2]::int, m[1]::int);
  end if;
  m := regexp_match(s, '^(\d{4})-(\d{2})-(\d{2})');
  if m is not null then return make_date(m[1]::int, m[2]::int, m[3]::int); end if;
  if s ~ '^\d{5}$' then return date '1899-12-30' + s::int; end if;
  return null;
exception when others then
  return null;
end $$;

-- «1 - Factura A», «001» o el nombre del tipo
create or replace function fiscal.tipo_flexible(p_txt text)
returns int language sql stable as $$
  select coalesce(
    (regexp_match(fiscal.norm_cab(p_txt), '^(\d{1,3})\y'))[1]::int,
    (select t.codigo from fiscal.tipo_comprobante t
     where position(fiscal.norm_cab(t.descripcion) in fiscal.norm_cab(p_txt)) > 0
     order by length(t.descripcion) desc limit 1))
$$;

-- Lee el archivo de «Mis Comprobantes» (filas ya separadas). Detecta la fila de títulos y las columnas por su nombre.
create or replace function fiscal.leer_mis_comprobantes(p_filas jsonb, p_tipo_archivo text)
returns jsonb language plpgsql stable as $$
declare
  v_alias jsonb := '{
    "fecha": ["fecha", "fecha de emision", "fecha emision"],
    "tipo": ["tipo", "tipo de comprobante", "tipo comprobante"],
    "pv": ["punto de venta", "pto venta", "punto venta", "pto de venta"],
    "numero": ["numero desde", "nro desde", "numero", "numero de comprobante", "nro comprobante"],
    "numero_hasta": ["numero hasta", "nro hasta"],
    "cae": ["cod autorizacion", "codigo de autorizacion", "codigo autorizacion", "cae", "cod de autorizacion"],
    "tipo_doc": ["tipo doc emisor", "tipo doc receptor", "tipo documento emisor", "tipo documento receptor", "tipo doc"],
    "nro_doc": ["nro doc emisor", "nro doc receptor", "numero doc emisor", "numero doc receptor", "nro documento emisor", "nro documento receptor", "cuit emisor", "cuit receptor", "nro doc"],
    "nombre": ["denominacion emisor", "denominacion receptor", "denominacion", "razon social"],
    "tipo_cambio": ["tipo cambio", "tipo de cambio"],
    "moneda": ["moneda"],
    "neto_gravado": ["imp neto gravado", "neto gravado", "total neto gravado", "importe neto gravado", "imp neto gravado total"],
    "no_gravado": ["imp neto no gravado", "neto no gravado", "importe neto no gravado"],
    "exento": ["imp op exentas", "op exentas", "importe op exentas", "exento", "imp exento"],
    "otros_tributos": ["otros tributos", "imp otros tributos", "importe otros tributos"],
    "iva": ["iva", "total iva", "imp iva", "importe iva"],
    "total": ["imp total", "importe total", "total"]}';
  v_pct jsonb := '{"0": 0, "2,5": 2.5, "2.5": 2.5, "5": 5, "10,5": 10.5, "10.5": 10.5, "21": 21, "27": 27}';
  v_nombres jsonb := '{"fecha": "Fecha", "tipo": "Tipo", "pv": "Punto de Venta", "numero": "Número Desde", "total": "Imp. Total"}';
  v_errores jsonb := '[]';
  v_comp jsonb := '[]';
  n int := jsonb_array_length(coalesce(p_filas, '[]'));
  i_cab int := -1;
  h text[];
  cab text[];
  idx jsonb := '{}';
  ali jsonb := '{}';
  v_detalle boolean;
  k text; arr jsonb; m text; pct text;
  f jsonb; obs jsonb;
  v_fecha date; v_tipo int; v_t fiscal.tipo_comprobante; v_pv numeric; v_num numeric;
  v_neto numeric; v_nograv numeric; v_exento numeric; v_otros numeric; v_iva numeric; v_total numeric;
  v_moneda text; v_cot numeric; v_desglose jsonb; v_base numeric; v_iva_a numeric; v_p numeric; v_resto numeric;
begin
  for i in 0 .. least(n, 15) - 1 loop
    h := array(select fiscal.norm_cab(x) from jsonb_array_elements_text(p_filas->i) with ordinality e(x, o) order by o);
    if 'fecha' = any(h) and exists (select 1 from unnest(h) x where x like 'tipo%') then i_cab := i; cab := h; exit; end if;
  end loop;
  if i_cab < 0 then
    return jsonb_build_object('comprobantes', '[]'::jsonb, 'columnas', '[]'::jsonb, 'detalle_alicuotas', false, 'fila_titulos', null,
      'errores', jsonb_build_array('No se encontró la fila de títulos (tiene que tener al menos «Fecha» y «Tipo»). ¿Es el archivo de «Mis Comprobantes»?'));
  end if;
  for j in 1 .. coalesce(array_length(cab, 1), 0) loop
    for k, arr in select key, value from jsonb_each(v_alias) loop
      if not idx ? k and arr ? cab[j] then idx := idx || jsonb_build_object(k, j - 1); end if;
    end loop;
    m := (regexp_match(cab[j], '(\d+(?:[.,]\d+)?)\s*%'))[1];
    if m is not null and v_pct ? m then
      pct := (v_pct->>m)::numeric::text;
      if cab[j] like '%neto%' then
        ali := ali || jsonb_build_object(pct, coalesce(ali->pct, '{}') || jsonb_build_object('neto', j - 1));
      elsif cab[j] like 'iva%' or cab[j] like 'imp iva%' then
        ali := ali || jsonb_build_object(pct, coalesce(ali->pct, '{}') || jsonb_build_object('iva', j - 1));
      end if;
    end if;
  end loop;
  v_detalle := exists (select 1 from jsonb_each(ali) e where e.value ? 'neto');
  for k in select x from unnest(array['fecha', 'tipo', 'pv', 'numero', 'total']) x loop
    if not idx ? k then v_errores := v_errores || to_jsonb(format('Falta la columna «%s».', v_nombres->>k)); end if;
  end loop;
  if jsonb_array_length(v_errores) = 0 then
    for i in i_cab + 1 .. n - 1 loop
      f := p_filas->i;
      continue when btrim(coalesce(f->>((idx->>'fecha')::int), '')) = '';
      obs := '[]';
      v_fecha := fiscal.fecha_flexible(f->>((idx->>'fecha')::int));
      v_tipo := fiscal.tipo_flexible(f->>((idx->>'tipo')::int));
      select * into v_t from fiscal.tipo_comprobante where codigo = v_tipo;
      v_pv := coalesce(nullif(regexp_replace(coalesce(f->>((idx->>'pv')::int), ''), '\D', '', 'g'), '')::numeric, 0);
      v_num := coalesce(nullif(regexp_replace(coalesce(f->>((idx->>'numero')::int), ''), '\D', '', 'g'), '')::numeric, 0);
      if v_fecha is null or v_t.codigo is null or v_pv = 0 or v_num = 0 or v_pv > 99999 or v_num > 99999999 then
        v_errores := v_errores || to_jsonb(format('Fila %s: no se pudo leer la fecha, el tipo o el número.', i + 1));
        continue;
      end if;
      v_neto := case when idx ? 'neto_gravado' then abs(coalesce(fiscal.importe_flexible(f->>((idx->>'neto_gravado')::int)), 0)) else 0 end;
      v_nograv := case when idx ? 'no_gravado' then abs(coalesce(fiscal.importe_flexible(f->>((idx->>'no_gravado')::int)), 0)) else 0 end;
      v_exento := case when idx ? 'exento' then abs(coalesce(fiscal.importe_flexible(f->>((idx->>'exento')::int)), 0)) else 0 end;
      v_otros := case when idx ? 'otros_tributos' then abs(coalesce(fiscal.importe_flexible(f->>((idx->>'otros_tributos')::int)), 0)) else 0 end;
      v_iva := case when idx ? 'iva' then abs(coalesce(fiscal.importe_flexible(f->>((idx->>'iva')::int)), 0)) else 0 end;
      v_total := abs(coalesce(fiscal.importe_flexible(f->>((idx->>'total')::int)), 0));
      v_moneda := case when coalesce(f->>((idx->>'moneda')::int), '') ~* 'usd|dol|u\$s|us\$' then 'DOL' else 'PES' end;
      v_cot := case when v_moneda = 'PES' then 1 else fiscal.cotizacion_flexible(f->>((idx->>'tipo_cambio')::int)) end;
      v_desglose := null;
      if v_detalle then
        v_desglose := '[]';
        for pct, arr in select key, value from jsonb_each(ali) order by key::numeric desc loop
          v_base := case when arr ? 'neto' then abs(coalesce(fiscal.importe_flexible(f->>((arr->>'neto')::int)), 0)) else 0 end;
          v_iva_a := case when arr ? 'iva' then abs(coalesce(fiscal.importe_flexible(f->>((arr->>'iva')::int)), 0)) else 0 end;
          if v_base <> 0 then
            v_desglose := v_desglose || jsonb_build_object('alicuota_codigo', (select codigo from fiscal.alicuota where porcentaje = pct::numeric), 'base', v_base, 'iva', v_iva_a);
          end if;
        end loop;
      elsif p_tipo_archivo = 'recibidos' and not v_t.discrimina_iva then
        v_desglose := '[]';   -- B y C recibidas: sin crédito fiscal, todo va a no gravado (R-52)
      elsif v_iva = 0 then
        v_desglose := case when v_neto = 0 then '[]'::jsonb else jsonb_build_array(jsonb_build_object('alicuota_codigo', 3, 'base', v_neto, 'iva', 0)) end;
      else
        select p into v_p from unnest(array[21, 10.5, 27, 5, 2.5]::numeric[]) with ordinality x(p, o) where fiscal.calcular_iva(v_neto, p) = v_iva order by o limit 1;
        if v_p is not null then
          v_desglose := jsonb_build_array(jsonb_build_object('alicuota_codigo', (select codigo from fiscal.alicuota where porcentaje = v_p), 'base', v_neto, 'iva', v_iva));
        else
          obs := obs || to_jsonb('El archivo no trae el detalle por alícuota y el IVA no corresponde a una sola alícuota: hay que cargar el desglose a mano.'::text);
        end if;
      end if;
      if p_tipo_archivo = 'recibidos' and not v_t.discrimina_iva then
        v_nograv := v_total - v_otros; v_neto := 0; v_exento := 0; v_iva := 0;
      end if;
      v_resto := v_total - (v_neto + v_nograv + v_exento + v_iva + v_otros);
      if abs(v_resto) > 0.01 then
        v_otros := v_otros + v_resto;
        obs := obs || to_jsonb(format('El total supera la suma de los importes en %s: se tomó como otros tributos o percepciones. Revisá si es una percepción de IVA o de Ingresos Brutos.', fiscal.importe_texto(v_resto)));
      end if;
      v_comp := v_comp || jsonb_build_object(
        'fila', i + 1, 'fecha', v_fecha, 'tipo', v_tipo, 'punto_venta', v_pv::int, 'numero', v_num::int,
        'cae', btrim(coalesce(f->>((idx->>'cae')::int), '')),
        'tipo_doc', coalesce(nullif(regexp_replace(coalesce(f->>((idx->>'tipo_doc')::int), ''), '\D', '', 'g'), '')::int, 80),
        'cuit', regexp_replace(coalesce(f->>((idx->>'nro_doc')::int), ''), '\D', '', 'g'),
        'nombre', btrim(coalesce(f->>((idx->>'nombre')::int), '')),
        'moneda', v_moneda, 'cotizacion', v_cot,
        'neto_gravado', v_neto, 'no_gravado', v_nograv, 'exento', v_exento, 'otros_tributos', v_otros, 'iva', v_iva, 'total', v_total,
        'desglose', v_desglose, 'observaciones', obs);
    end loop;
  end if;
  return jsonb_build_object('comprobantes', v_comp, 'errores', v_errores, 'columnas', (select coalesce(jsonb_agg(key), '[]') from jsonb_object_keys(idx) key),
    'detalle_alicuotas', v_detalle, 'fila_titulos', i_cab + 1);
end $$;

-- ---------------------------------------------------------------------
-- Conciliación: compara lo de ARCA con lo cargado para una empresa y un período
-- ---------------------------------------------------------------------
create or replace function fiscal.conciliar(p_empresa text, p_periodo text, p_tipo_archivo text, p_comprobantes jsonb)
returns jsonb language plpgsql stable as $$
declare
  v_op text := case when p_tipo_archivo = 'recibidos' then 'compra' else 'venta' end;
  v_filas jsonb := '[]';
  v_usados uuid[] := '{}';
  v_en jsonb;
  a jsonb;
  s fiscal.comprobante;
  t fiscal.tipo_comprobante;
  v_etiqueta text;
  v_dif jsonb; v_notas jsonb;
  v_fecha date;
  v_lib jsonb;
  v_tot_arca jsonb;
  v_res jsonb;
  fmt_fecha constant text := 'DD/MM/YYYY';
begin
  select coalesce(jsonb_agg(x order by o), '[]') into v_en from jsonb_array_elements(p_comprobantes) with ordinality e(x, o)
  where to_char((x->>'fecha')::date, 'YYYY-MM') = p_periodo;
  for a in select x from jsonb_array_elements(v_en) x loop
    select * into t from fiscal.tipo_comprobante where codigo = (a->>'tipo')::int;
    v_etiqueta := t.descripcion || ' ' || fiscal.numero_comprobante((a->>'punto_venta')::int, (a->>'numero')::int);
    v_fecha := (a->>'fecha')::date;
    s := null;
    if v_op = 'compra' then
      select * into s from fiscal.comprobante c
      where c.operacion = 'compra' and c.empresa_id = p_empresa and c.contraparte_doc = a->>'cuit' and c.tipo = t.codigo
        and c.punto_venta = (a->>'punto_venta')::int and c.numero = (a->>'numero')::int
      order by (c.estado = 'anulada'), c.creado_en limit 1;
    else
      select * into s from fiscal.comprobante c
      where c.operacion = 'venta' and c.empresa_id = p_empresa and c.estado <> 'borrador' and c.tipo = t.codigo
        and c.punto_venta = (a->>'punto_venta')::int and c.numero = (a->>'numero')::int
      limit 1;
    end if;
    if s.id is null then
      v_filas := v_filas || jsonb_build_object('estado', 'falta_sistema', 'arca', a, 'etiqueta', v_etiqueta,
        'contraparte', coalesce(nullif(a->>'nombre', ''), fiscal.formatear_cuit(a->>'cuit')), 'cuit', a->>'cuit',
        'detalle', case when jsonb_array_length(a->'observaciones') > 0 then a->'observaciones'
                        when v_op = 'compra' then '["Está en ARCA y no está cargada: se puede importar como borrador."]'::jsonb
                        else '["Emitida por el sistema anterior: se puede importar como histórico para que el libro quede completo."]'::jsonb end,
        'importable', jsonb_typeof(a->'desglose') = 'array');
      continue;
    end if;
    v_usados := v_usados || s.id;
    if s.estado = 'anulada' then
      v_filas := v_filas || jsonb_build_object('estado', 'anulada_sistema', 'arca', a, 'etiqueta', v_etiqueta, 'contraparte', s.contraparte_razon, 'cuit', a->>'cuit',
        'sistema', jsonb_build_object('id', s.id, 'etiqueta', fiscal.etiqueta(s), 'estado', s.estado, 'fecha', s.fecha, 'total', s.total, 'iva', s.iva),
        'detalle', '["Está anulada en el sistema pero ARCA la tiene: hay que excluirla en IVA Simple."]'::jsonb);
      continue;
    end if;
    v_dif := '[]'; v_notas := '[]';
    if s.total <> (a->>'total')::numeric then
      v_dif := v_dif || to_jsonb(format('Total: sistema %s, ARCA %s', fiscal.importe_texto(s.total), fiscal.importe_texto((a->>'total')::numeric)));
    end if;
    if (v_op = 'venta' or t.discrimina_iva) and s.iva <> (a->>'iva')::numeric then
      v_dif := v_dif || to_jsonb(format('IVA: sistema %s, ARCA %s', fiscal.importe_texto(s.iva), fiscal.importe_texto((a->>'iva')::numeric)));
    end if;
    if s.fecha <> v_fecha then
      v_dif := v_dif || to_jsonb(format('Fecha: sistema %s, ARCA %s', to_char(s.fecha, fmt_fecha), to_char(v_fecha, fmt_fecha)));
    end if;
    if v_op = 'venta' and coalesce(a->>'cuit', '') <> '' and coalesce(s.contraparte_tipo_doc, 0) <> 99 and s.contraparte_doc is distinct from a->>'cuit' then
      v_dif := v_dif || to_jsonb(format('Cliente: sistema %s, ARCA %s', fiscal.formatear_cuit(s.contraparte_doc), fiscal.formatear_cuit(a->>'cuit')));
    end if;
    if v_op = 'compra' and s.periodo <> p_periodo then
      v_notas := v_notas || to_jsonb(format('En el sistema está imputada a %s: es un ajuste para IVA Simple.', s.periodo));
    end if;
    if v_op = 'compra' and s.estado = 'borrador' then
      v_notas := v_notas || to_jsonb('Está cargada pero en borrador: no suma crédito fiscal hasta confirmarla.'::text);
    end if;
    v_filas := v_filas || jsonb_build_object(
      'estado', case when jsonb_array_length(v_dif) > 0 then 'difiere' when s.estado = 'borrador' then 'en_borrador' else 'coincide' end,
      'arca', a, 'etiqueta', v_etiqueta, 'contraparte', s.contraparte_razon, 'cuit', a->>'cuit',
      'sistema', jsonb_build_object('id', s.id, 'etiqueta', fiscal.etiqueta(s), 'estado', s.estado, 'fecha', s.fecha, 'total', s.total, 'iva', s.iva),
      'detalle', v_dif || v_notas);
  end loop;
  -- Lo cargado en el sistema que ARCA no tiene
  for s in select * from fiscal.comprobante c
           where c.operacion = v_op and c.empresa_id = p_empresa and to_char(c.fecha, 'YYYY-MM') = p_periodo and not (c.id = any(v_usados))
             and c.estado not in ('anulada', case when v_op = 'venta' then 'borrador' else 'anulada' end)
           order by c.fecha loop
    v_filas := v_filas || jsonb_build_object('estado', 'falta_arca', 'etiqueta', fiscal.etiqueta(s), 'contraparte', s.contraparte_razon, 'cuit', s.contraparte_doc,
      'sistema', jsonb_build_object('id', s.id, 'etiqueta', fiscal.etiqueta(s), 'estado', s.estado, 'fecha', s.fecha, 'total', s.total, 'iva', s.iva),
      'detalle', jsonb_build_array(case
        when v_op = 'compra' then 'Está cargada en el sistema y ARCA no la tiene: revisala con el proveedor antes de computar el crédito.'
        when s.estado = 'emitido_sin_cae' then 'Emitida sin CAE en el prototipo: ARCA no la tiene. En producción, toda factura emitida tiene que aparecer en ARCA.'
        else 'Está en el sistema y ARCA no la tiene: revisar.' end));
  end loop;
  select coalesce(jsonb_agg(x order by case x->>'estado' when 'difiere' then 0 when 'falta_sistema' then 1 when 'falta_arca' then 2
                                         when 'anulada_sistema' then 3 when 'en_borrador' then 4 else 5 end, x->>'etiqueta'), '[]')
  into v_filas from jsonb_array_elements(v_filas) x;
  select jsonb_object_agg(e, (select count(*) from jsonb_array_elements(v_filas) x where x->>'estado' = e))
  into v_res from unnest(array['coincide', 'difiere', 'falta_sistema', 'falta_arca', 'anulada_sistema', 'en_borrador']) e;
  -- Las notas de crédito restan, igual que en el libro (conSigno)
  select jsonb_build_object(
    'neto', coalesce(sum(tc.signo * ((x->>'neto_gravado')::numeric + (x->>'no_gravado')::numeric + (x->>'exento')::numeric)), 0),
    'iva', coalesce(sum(tc.signo * (x->>'iva')::numeric), 0),
    'total', coalesce(sum(tc.signo * (x->>'total')::numeric), 0))
  into v_tot_arca from jsonb_array_elements(v_en) x join fiscal.tipo_comprobante tc on tc.codigo = (x->>'tipo')::int;
  v_lib := fiscal.libro_json(p_empresa, p_periodo, v_op)->'totales';
  return jsonb_build_object('filas', v_filas, 'fuera', jsonb_array_length(p_comprobantes) - jsonb_array_length(v_en), 'resumen', v_res,
    'tot_arca', v_tot_arca,
    'tot_sistema', jsonb_build_object(
      'neto', (v_lib->>'n21')::numeric + (v_lib->>'n105')::numeric + (v_lib->>'n27')::numeric + (v_lib->>'n_otras')::numeric
              + (v_lib->>'n0')::numeric + (v_lib->>'no_gravado')::numeric + (v_lib->>'exento')::numeric,
      'iva', (v_lib->>'iva')::numeric, 'total', (v_lib->>'total')::numeric));
end $$;

-- Guarda que se hizo la conciliación (para el cierre y para IVA Simple)
create or replace function fiscal.registrar_conciliacion(p_rol text, p_empresa text, p_periodo text, p_tipo_archivo text, p_archivo text, p_conc jsonb)
returns void language plpgsql as $$
declare r jsonb := p_conc->'resumen';
begin
  insert into fiscal.conciliacion_arca (empresa_id, periodo, tipo_archivo, archivo, resumen, diferencias, tot_arca, tot_sistema, rol)
  values (p_empresa, p_periodo, p_tipo_archivo, coalesce(p_archivo, ''), r,
    coalesce((select jsonb_agg(x - 'arca') from jsonb_array_elements(p_conc->'filas') x where x->>'estado' <> 'coincide'), '[]'),
    p_conc->'tot_arca', p_conc->'tot_sistema', p_rol)
  on conflict (empresa_id, periodo, tipo_archivo) do update set archivo = excluded.archivo, resumen = excluded.resumen,
    diferencias = excluded.diferencias, tot_arca = excluded.tot_arca, tot_sistema = excluded.tot_sistema, rol = excluded.rol, cuando = now();
  perform fiscal.registrar(p_rol, p_empresa, 'concilió con ARCA', case when p_tipo_archivo = 'recibidos' then 'compras' else 'ventas' end, p_periodo,
    format('%s · %s coinciden, %s difieren, %s faltan en el sistema, %s faltan en ARCA', coalesce(nullif(p_archivo, ''), 'archivo sin nombre'),
      r->>'coincide', r->>'difiere', r->>'falta_sistema', r->>'falta_arca'));
end $$;

-- Confirma un borrador de compra que ya pasó las validaciones al guardarse
create or replace function fiscal.confirmar_compra(p_rol text, p_id uuid)
returns fiscal.comprobante language plpgsql as $$
declare c fiscal.comprobante;
begin
  perform fiscal.exigir(p_rol, 'cargar_compra');
  select * into c from fiscal.comprobante where id = p_id and operacion = 'compra' for update;
  perform fiscal.req(c.id is not null, 'NO_ENCONTRADO', 'El comprobante no existe.');
  perform fiscal.req(c.estado = 'borrador', 'ESTADO_INVALIDO', format('La compra %s ya está %s.', fiscal.etiqueta(c), c.estado));
  perform fiscal.req(c.imagen_path is not null or c.cae <> '' or c.codigo_autorizacion <> '', 'ADJUNTO_OBLIGATORIO',
    'Falta la imagen o el PDF de la factura, su CAE o el código de autorización de ARCA.', 'imagen');
  perform fiscal.exigir_periodo_abierto(c.empresa_id, c.periodo, 'confirmar una compra imputada a ese mes');
  update fiscal.comprobante set estado = 'confirmada', confirmado_en = now() where id = p_id returning * into c;
  perform fiscal.registrar(p_rol, c.empresa_id, 'confirmó', 'factura de compra', fiscal.etiqueta(c),
    format('%s · %s', c.contraparte_razon, fiscal.importe_texto(c.total)));
  return c;
end $$;

-- ---------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------
-- Lee el archivo, concilia y deja registrada la conciliación. No cambia comprobantes.
create or replace function public.conciliar_arca(p_rol text, p_empresa text, p_periodo text, p_tipo_archivo text, p_archivo text, p_texto text)
returns jsonb language plpgsql security definer set search_path = fiscal, pg_temp as $$
declare v_lec jsonb; v_conc jsonb := null;
begin
  perform fiscal.req(exists (select 1 from fiscal.rol where id = p_rol), 'PROHIBIDO', 'Elegí un rol válido.');
  perform fiscal.req(exists (select 1 from fiscal.empresa where id = p_empresa), 'NO_ENCONTRADO', 'La empresa no existe.');
  perform fiscal.req(p_periodo ~ '^\d{4}-(0[1-9]|1[0-2])$', 'VALIDACION', 'El período no es válido.', 'periodo');
  perform fiscal.req(p_tipo_archivo in ('recibidos', 'emitidos'), 'VALIDACION', 'El archivo es de comprobantes recibidos o emitidos.', 'tipo_archivo');
  perform fiscal.req(btrim(coalesce(p_texto, '')) <> '', 'VALIDACION', 'El archivo está vacío.', 'archivo');
  v_lec := fiscal.leer_mis_comprobantes(fiscal.parsear_csv(p_texto), p_tipo_archivo);
  if jsonb_array_length(v_lec->'comprobantes') > 0 then
    v_conc := fiscal.conciliar(p_empresa, p_periodo, p_tipo_archivo, v_lec->'comprobantes');
    perform fiscal.registrar_conciliacion(p_rol, p_empresa, p_periodo, p_tipo_archivo, p_archivo, v_conc);
  end if;
  return jsonb_build_object('lectura', v_lec - 'comprobantes' || jsonb_build_object('cantidad', jsonb_array_length(v_lec->'comprobantes')),
    'comprobantes', v_lec->'comprobantes', 'conciliacion', v_conc);
end $$;

-- Importa los comprobantes que faltan en el sistema. Las compras quedan en borrador para completar (US-064);
-- las ventas del sistema anterior quedan como histórico autorizado, para que el libro quede completo.
create or replace function public.importar_desde_arca(p_rol text, p_empresa text, p_tipo_archivo text, p_comprobantes jsonb)
returns jsonb language plpgsql security definer set search_path = fiscal, pg_temp as $$
declare
  v_emp fiscal.empresa;
  a jsonb;
  t fiscal.tipo_comprobante;
  v_etiqueta text;
  v_creados jsonb := '[]';
  v_errores jsonb := '[]';
  v_cp fiscal.contraparte;
  v_cae text;
  v_r jsonb;
  v_id uuid;
  v_imp jsonb;
  v_c fiscal.comprobante;
  v_detalle text;
begin
  perform fiscal.exigir(p_rol, 'importar_arca');
  select * into v_emp from fiscal.empresa where id = p_empresa;
  perform fiscal.req(v_emp.id is not null, 'NO_ENCONTRADO', 'La empresa no existe.');
  perform fiscal.req(p_tipo_archivo in ('recibidos', 'emitidos'), 'VALIDACION', 'El archivo es de comprobantes recibidos o emitidos.', 'tipo_archivo');
  for a in select x from jsonb_array_elements(coalesce(p_comprobantes, '[]')) x loop
    select * into t from fiscal.tipo_comprobante where codigo = (a->>'tipo')::int;
    v_etiqueta := coalesce(t.descripcion, 'Comprobante') || ' ' || fiscal.numero_comprobante((a->>'punto_venta')::int, (a->>'numero')::int);
    v_cae := btrim(coalesce(a->>'cae', ''));
    begin
      perform fiscal.req(jsonb_typeof(a->'desglose') = 'array', 'VALIDACION', 'No se puede importar sin el desglose por alícuota: cargala a mano.');
      v_cp := null;
      if p_tipo_archivo = 'recibidos' then
        select * into v_cp from fiscal.contraparte where tipo_doc = 80 and numero_doc = a->>'cuit' order by es_proveedor desc limit 1;
        if v_cp.id is null then
          perform fiscal.req(fiscal.cuit_valido(a->>'cuit'), 'CUIT_INVALIDO', format('El CUIT %s del archivo no es válido.', a->>'cuit'));
          insert into fiscal.contraparte (nombre, es_proveedor, tipo_doc, numero_doc, razon_social, condicion_iva)
          values (coalesce(nullif(a->>'nombre', ''), fiscal.formatear_cuit(a->>'cuit')), true, 80, a->>'cuit',
                  coalesce(nullif(a->>'nombre', ''), fiscal.formatear_cuit(a->>'cuit')), case t.letra when 'C' then 6 when 'B' then 4 else 1 end)
          returning * into v_cp;
          perform fiscal.registrar(p_rol, p_empresa, 'creó desde ARCA', 'proveedor', v_cp.nombre,
            format('CUIT %s · condición supuesta por la letra de la factura: revisarla', fiscal.formatear_cuit(v_cp.numero_doc)));
        elsif not v_cp.es_proveedor then
          update fiscal.contraparte set es_proveedor = true, actualizado_en = now() where id = v_cp.id;
        end if;
        v_r := public.guardar_compra(p_rol, jsonb_build_object(
          'empresa_id', p_empresa, 'contraparte_id', v_cp.id, 'tipo', t.codigo, 'punto_venta', a->'punto_venta', 'numero', a->'numero',
          'fecha', a->>'fecha', 'periodo', to_char((a->>'fecha')::date, 'YYYY-MM'),
          'desglose', (select coalesce(jsonb_agg(jsonb_build_object('alicuota_codigo', d->'alicuota_codigo', 'base', (d->>'base')::numeric::text)), '[]') from jsonb_array_elements(a->'desglose') d),
          'no_gravado', (a->>'no_gravado')::numeric::text, 'exento', (a->>'exento')::numeric::text, 'otros_tributos', (a->>'otros_tributos')::numeric::text,
          'cae', case when v_cae ~ '^\d{14}$' then v_cae else '' end,
          'observaciones', 'Importada desde ARCA («Mis Comprobantes»)' || case when a->>'moneda' = 'DOL'
            then format('. En el archivo está en dólares, cotización %s: revisar.', a->>'cotizacion') else '' end), false);
        update fiscal.comprobante set origen = 'arca', codigo_autorizacion = v_cae where id = (v_r->>'id')::uuid;
        -- el IVA del archivo manda: si difiere del recalculado se avisa
        if (v_r->>'iva')::numeric <> (a->>'iva')::numeric then
          v_errores := v_errores || to_jsonb(format('%s: el IVA recalculado (%s) no coincide con el del archivo (%s). Revisá el borrador.',
            v_etiqueta, fiscal.importe_texto((v_r->>'iva')::numeric), fiscal.importe_texto((a->>'iva')::numeric)));
        end if;
        v_creados := v_creados || jsonb_build_object('id', v_r->>'id', 'etiqueta', v_r->>'etiqueta', 'estado', v_r->>'estado', 'total', v_r->'total');
      else
        perform fiscal.req(t.venta, 'TIPO_INVALIDO', 'Ese tipo de comprobante no es de venta.');
        if coalesce(a->>'cuit', '') not in ('', '0') then
          select * into v_cp from fiscal.contraparte where numero_doc = a->>'cuit' order by es_cliente desc limit 1;
        end if;
        if v_cp.id is null and ((a->>'tipo_doc')::int = 99 or coalesce(a->>'cuit', '') in ('', '0')) then
          select * into v_cp from fiscal.contraparte where es_cliente and tipo_doc = 99 limit 1;
        end if;
        if v_cp.id is null then
          perform fiscal.req(fiscal.cuit_valido(a->>'cuit'), 'CUIT_INVALIDO', format('El CUIT %s del archivo no es válido.', a->>'cuit'));
          insert into fiscal.contraparte (nombre, es_cliente, tipo_doc, numero_doc, razon_social, condicion_iva)
          values (coalesce(nullif(a->>'nombre', ''), fiscal.formatear_cuit(a->>'cuit')), true, 80, a->>'cuit',
                  coalesce(nullif(a->>'nombre', ''), fiscal.formatear_cuit(a->>'cuit')), case when t.letra = 'B' then 5 else 1 end)
          returning * into v_cp;
          perform fiscal.registrar(p_rol, p_empresa, 'creó desde ARCA', 'cliente', v_cp.nombre,
            format('CUIT %s · condición supuesta: revisarla', fiscal.formatear_cuit(v_cp.numero_doc)));
        elsif not v_cp.es_cliente then
          update fiscal.contraparte set es_cliente = true, actualizado_en = now() where id = v_cp.id;
        end if;
        perform fiscal.req(not exists (select 1 from fiscal.comprobante where operacion = 'venta' and empresa_id = p_empresa and tipo = t.codigo
          and punto_venta = (a->>'punto_venta')::int and numero = (a->>'numero')::int), 'NUMERO_DUPLICADO', 'Ese comprobante ya está en el sistema.');
        perform fiscal.exigir_periodo_abierto(p_empresa, to_char((a->>'fecha')::date, 'YYYY-MM'), 'importar un comprobante de ese mes');
        v_imp := fiscal.importes_desde_desglose(a->'desglose', jsonb_build_object('no_gravado', (a->>'no_gravado')::numeric::text,
          'exento', (a->>'exento')::numeric::text, 'otros_tributos', (a->>'otros_tributos')::numeric::text));
        insert into fiscal.comprobante (operacion, empresa_id, contraparte_id, tipo, punto_venta, numero, fecha, periodo, estado, origen, creado_rol,
          cae, codigo_autorizacion, observaciones, moneda, cotizacion,
          contraparte_tipo_doc, contraparte_doc, contraparte_razon, contraparte_condicion_iva, contraparte_domicilio,
          neto_gravado, no_gravado, exento, iva, otros_tributos, total)
        values ('venta', p_empresa, v_cp.id, t.codigo, (a->>'punto_venta')::int, (a->>'numero')::int, (a->>'fecha')::date,
          to_char((a->>'fecha')::date, 'YYYY-MM'), 'borrador', 'arca', p_rol,
          case when v_cae ~ '^\d{14}$' then v_cae else '' end, v_cae, 'Emitida con el sistema de facturación anterior (importada desde ARCA)',
          case when a->>'moneda' = 'DOL' then 'USD' else 'ARS' end, coalesce((a->>'cotizacion')::numeric, 1),
          v_cp.tipo_doc, v_cp.numero_doc, coalesce(v_cp.razon_social, v_cp.nombre), v_cp.condicion_iva, v_cp.domicilio,
          (v_imp->>'neto_gravado')::numeric, (v_imp->>'no_gravado')::numeric, (v_imp->>'exento')::numeric, (v_imp->>'iva')::numeric,
          (v_imp->>'otros_tributos')::numeric, (v_imp->>'total')::numeric)
        returning id into v_id;
        perform fiscal.guardar_detalle(v_id,
          (select coalesce(jsonb_agg(jsonb_build_object('orden', o, 'codigo', '', 'descripcion', 'Comprobante emitido con el sistema anterior (importado de ARCA)',
             'cantidad', 1, 'precio_lista', d->'base', 'descuento', 0, 'precio_unitario', d->'base', 'alicuota_codigo', d->'alicuota_codigo', 'importe_neto', d->'base')), '[]')
           from jsonb_array_elements(a->'desglose') with ordinality e(d, o)),
          a->'desglose');
        update fiscal.comprobante set estado = 'autorizado', emitido_en = (a->>'fecha')::date + time '12:00' where id = v_id returning * into v_c;
        perform fiscal.registrar(p_rol, p_empresa, 'importó de ARCA', 'factura de venta (sistema anterior)', fiscal.etiqueta(v_c), v_c.contraparte_razon);
        v_creados := v_creados || jsonb_build_object('id', v_id, 'etiqueta', fiscal.etiqueta(v_c), 'estado', v_c.estado, 'total', v_c.total);
      end if;
    exception when others then
      get stacked diagnostics v_detalle = pg_exception_detail;
      v_errores := v_errores || to_jsonb(format('%s: %s', v_etiqueta, coalesce(nullif(v_detalle, ''), sqlerrm)));
    end;
  end loop;
  return jsonb_build_object('creados', v_creados, 'errores', v_errores);
end $$;

-- Confirma de una vez los borradores importados de ARCA que ya están completos
create or replace function public.confirmar_importadas(p_rol text, p_empresa text)
returns jsonb language plpgsql security definer set search_path = fiscal, pg_temp as $$
declare
  c fiscal.comprobante;
  v_ok jsonb := '[]';
  v_pend jsonb := '[]';
  v_detalle text;
begin
  perform fiscal.exigir(p_rol, 'cargar_compra');
  for c in select * from fiscal.comprobante where operacion = 'compra' and empresa_id = p_empresa and estado = 'borrador' and origen = 'arca' order by fecha, numero loop
    begin
      perform fiscal.confirmar_compra(p_rol, c.id);
      v_ok := v_ok || jsonb_build_object('id', c.id, 'etiqueta', fiscal.etiqueta(c));
    exception when others then
      get stacked diagnostics v_detalle = pg_exception_detail;
      v_pend := v_pend || jsonb_build_object('id', c.id, 'etiqueta', fiscal.etiqueta(c), 'motivo', coalesce(nullif(v_detalle, ''), sqlerrm));
    end;
  end loop;
  return jsonb_build_object('ok', v_ok, 'pendientes', v_pend);
end $$;

-- Archivo de ejemplo con el formato de «Mis Comprobantes» (datos ficticios), armado desde lo que hay en el sistema
-- más algunos casos para mostrar cada situación de la conciliación (solo Mecánica Pesada, octubre de 2026).
create or replace function public.archivo_ejemplo_arca(p_empresa text, p_periodo text, p_tipo_archivo text)
returns text language plpgsql security definer set search_path = fiscal, pg_temp as $$
declare
  v_rec boolean := p_tipo_archivo = 'recibidos';
  v_extras boolean := p_empresa = 'MP' and p_periodo = '2026-10';
  v_filas text[] := '{}';
  n int := 0;
  c record;
  o record;
begin
  v_filas := v_filas || array_to_string(array['Fecha', 'Tipo', 'Punto de Venta', 'Número Desde', 'Número Hasta', 'Cód. Autorización',
    case when v_rec then 'Tipo Doc. Emisor' else 'Tipo Doc. Receptor' end, case when v_rec then 'Nro. Doc. Emisor' else 'Nro. Doc. Receptor' end,
    case when v_rec then 'Denominación Emisor' else 'Denominación Receptor' end, 'Tipo Cambio', 'Moneda', 'Imp. Neto Gravado', 'Imp. Neto No Gravado',
    'Imp. Op. Exentas', 'Otros Tributos', 'IVA', 'Imp. Total'], ';');
  for o in
    select * from (
      select x.fecha, x.tipo, x.punto_venta as pv, x.numero, coalesce(x.contraparte_tipo_doc, 80) as tipo_doc,
        case when x.contraparte_tipo_doc = 99 then '0' else coalesce(x.contraparte_doc, '') end as cuit, x.contraparte_razon as nombre, x.moneda, x.cotizacion,
        case when not v_rec or t.discrimina_iva then x.neto_gravado else 0 end as neto,
        case when not v_rec or t.discrimina_iva then x.no_gravado else x.no_gravado + x.neto_gravado end as no_gravado, x.exento,
        x.otros_tributos + case when v_rec then x.percepcion_iva + x.percepcion_iibb else 0 end as otros, x.iva, x.total, 0 as orden
      from fiscal.comprobante x join fiscal.tipo_comprobante t on t.codigo = x.tipo
      where x.empresa_id = p_empresa and x.operacion = case when v_rec then 'compra' else 'venta' end and x.estado <> 'borrador'
        and x.origen <> 'arca' and to_char(x.fecha, 'YYYY-MM') = p_periodo
      union all
      select e.* from (values
        (date '2026-10-15', 1, 7, 880, 80, '30999999952', 'Fundición de Prueba S.R.L.', 'ARS', 1::numeric, 180000.00, 0::numeric, 0::numeric, 0::numeric, 37800.00, 217800.00, 1),
        (date '2026-10-19', 1, 5, 1300, 80, '33999999943', 'Repuestos Ficticios S.A.', 'ARS', 1, 40000.00, 0, 0, 0, 8400.00, 48400.00, 2),
        (date '2026-10-20', 1, 2, 4567, 80, '30999999960', 'Servicios Eléctricos Ejemplo S.A.', 'ARS', 1, 35000.00, 0, 0, 0, 9450.00, 44450.00, 3),
        (date '2026-10-20', 1, 5, 1310, 80, '33999999943', 'Repuestos Ficticios S.A.', 'ARS', 1, 100000.00, 0, 0, 0, 15750.00, 115750.00, 4)
      ) e(fecha, tipo, pv, numero, tipo_doc, cuit, nombre, moneda, cotizacion, neto, no_gravado, exento, otros, iva, total, orden)
      where v_extras and v_rec
      union all
      select date '2026-10-02', 1, 2, 101, 80, '30999999928', 'Transportes Ejemplo S.A.', 'ARS', 1, 250000.00, 0, 0, 0, 52500.00, 302500.00, 1
      where v_extras and not v_rec
    ) z order by z.orden, z.fecha, z.numero
  loop
    n := n + 1;
    v_filas := v_filas || array_to_string(array[
      -- en el ejemplo, la Factura A 00005-00001250 figura en ARCA con otra fecha (para mostrar una diferencia)
      to_char(case when v_extras and v_rec and o.orden = 0 and o.tipo = 1 and o.pv = 5 and o.numero = 1250 then date '2026-10-09' else o.fecha end, 'DD/MM/YYYY'),
      o.tipo || ' - ' || (select descripcion from fiscal.tipo_comprobante where codigo = o.tipo), o.pv::text, o.numero::text, o.numero::text,
      'FICTICIO-' || lpad(n::text, 6, '0'), o.tipo_doc::text, o.cuit, o.nombre,
      case when o.moneda = 'ARS' then '1,00' else replace(to_char(o.cotizacion, 'FM999999990.00'), '.', ',') end,
      case when o.moneda = 'ARS' then '$' else 'USD' end,
      replace(to_char(o.neto, 'FM999999999990.00'), '.', ','), replace(to_char(o.no_gravado, 'FM999999999990.00'), '.', ','),
      replace(to_char(o.exento, 'FM999999999990.00'), '.', ','), replace(to_char(o.otros, 'FM999999999990.00'), '.', ','),
      replace(to_char(o.iva, 'FM999999999990.00'), '.', ','), replace(to_char(o.total, 'FM999999999990.00'), '.', ',')], ';');
  end loop;
  return chr(65279) || array_to_string(v_filas, E'\r\n') || E'\r\n';
end $$;

-- guardar_compra: igual que antes, pero un borrador importado de ARCA se puede confirmar
-- con el código de autorización del archivo como respaldo (sin imagen ni CAE).
create or replace function public.guardar_compra(p_rol text, p_datos jsonb, p_confirmar boolean default false, p_clave uuid default null)
returns jsonb language plpgsql security definer set search_path = fiscal, pg_temp as $$
declare
  v_prev jsonb := fiscal.idem_buscar(p_clave, 'guardar_compra', p_datos || jsonb_build_object('confirmar', p_confirmar));
  v_id uuid := nullif(p_datos->>'id', '')::uuid;
  v_empresa fiscal.empresa;
  v_prov fiscal.contraparte;
  v_existente fiscal.comprobante;
  v_t fiscal.tipo_comprobante;
  v_pv int; v_numero int;
  v_fecha date;
  v_periodo text;
  v_calc jsonb;
  v_asoc fiscal.comprobante;
  v_dup fiscal.comprobante;
  v_imagen text := nullif(p_datos->>'imagen_path', '');
  v_cae text := coalesce(btrim(p_datos->>'cae'), '');
  v_c fiscal.comprobante;
begin
  if v_prev is not null then return v_prev; end if;
  perform fiscal.exigir(p_rol, 'cargar_compra');
  select * into v_empresa from fiscal.empresa where id = p_datos->>'empresa_id';
  perform fiscal.req(v_empresa.id is not null, 'NO_ENCONTRADO', 'La empresa no existe.');
  if v_id is not null then
    select * into v_existente from fiscal.comprobante where id = v_id and operacion = 'compra';
    perform fiscal.req(v_existente.id is not null, 'NO_ENCONTRADO', 'El comprobante no existe.');
    perform fiscal.req(v_existente.estado = 'borrador', 'COMPROBANTE_INMUTABLE',
      format('La compra %s ya está %s y no se puede editar.', fiscal.etiqueta(v_existente), v_existente.estado));
  end if;
  select * into v_prov from fiscal.contraparte where id = nullif(p_datos->>'contraparte_id', '')::uuid and es_proveedor;
  perform fiscal.req(v_prov.id is not null, 'VALIDACION', 'Elegí un proveedor.', 'contraparte_id');
  perform fiscal.req(v_prov.tipo_doc = 80 and fiscal.cuit_valido(v_prov.numero_doc) and v_prov.condicion_iva is not null, 'DATOS_FISCALES_INCOMPLETOS',
    format('El proveedor «%s» no tiene CUIT válido o condición frente al IVA. Completalo en Proveedores.', v_prov.nombre), 'contraparte_id');
  select * into v_t from fiscal.tipo_comprobante where codigo = nullif(p_datos->>'tipo', '')::int and compra;
  perform fiscal.req(v_t.codigo is not null, 'TIPO_INVALIDO', 'Elegí el tipo de comprobante.', 'tipo');
  begin v_pv := (p_datos->>'punto_venta')::int; exception when others then v_pv := null; end;
  perform fiscal.req(v_pv between 1 and 99999, 'VALIDACION', 'El punto de venta del proveedor va de 1 a 99999.', 'punto_venta');
  begin v_numero := (p_datos->>'numero')::int; exception when others then v_numero := null; end;
  perform fiscal.req(v_numero between 1 and 99999999, 'VALIDACION', 'El número va de 1 a 99999999.', 'numero');
  begin v_fecha := (p_datos->>'fecha')::date; exception when others then v_fecha := null; end;
  perform fiscal.req(v_fecha is not null, 'VALIDACION', 'Falta la fecha del comprobante.', 'fecha');
  v_periodo := coalesce(nullif(p_datos->>'periodo', ''), to_char(v_fecha, 'YYYY-MM'));
  perform fiscal.req(v_periodo ~ '^\d{4}-(0[1-9]|1[0-2])$', 'VALIDACION', 'El período de IVA no es válido.', 'periodo');
  perform fiscal.req(v_cae = '' or v_cae ~ '^\d{14}$', 'VALIDACION', 'El CAE tiene 14 dígitos.', 'cae');

  v_calc := fiscal.calcular_compra(v_t.codigo, p_datos->'desglose', p_datos);
  perform fiscal.req((v_calc->'importes'->>'total')::numeric > 0, 'VALIDACION', 'El total tiene que ser mayor que cero.', 'total');

  if v_t.clase <> 'factura' then
    select * into v_asoc from fiscal.comprobante where id = nullif(p_datos->>'asociado_id', '')::uuid and operacion = 'compra';
    perform fiscal.req(v_asoc.id is not null, 'NOTA_SIN_ASOCIADO', 'Una nota tiene que apuntar a la factura que corrige.', 'asociado_id');
    perform fiscal.req(v_asoc.estado = 'confirmada', 'ASOCIADO_BORRADOR', 'La nota apunta a una compra que no está confirmada.', 'asociado_id');
    perform fiscal.req(v_asoc.empresa_id = v_empresa.id, 'EMPRESA_DISTINTA', 'El comprobante asociado es de otra empresa.', 'asociado_id');
    perform fiscal.req(btrim(coalesce(p_datos->>'motivo', '')) <> '', 'MOTIVO_OBLIGATORIO', 'Toda nota exige un motivo.', 'motivo');
  end if;

  select * into v_dup from fiscal.comprobante
  where operacion = 'compra' and estado <> 'anulada' and empresa_id = v_empresa.id and contraparte_doc = v_prov.numero_doc
    and tipo = v_t.codigo and punto_venta = v_pv and numero = v_numero and id is distinct from v_id
  limit 1;
  perform fiscal.req(v_dup.id is null, 'NUMERO_DUPLICADO',
    format('Esa factura ya está cargada: %s de %s (%s). No se puede cargar dos veces.', fiscal.etiqueta(v_dup), v_prov.nombre, v_dup.estado), 'numero');

  if p_confirmar then
    perform fiscal.req(v_imagen is not null or v_cae <> '' or coalesce(v_existente.codigo_autorizacion, '') <> '', 'ADJUNTO_OBLIGATORIO',
      'Falta la imagen o el PDF de la factura, su CAE o el código de autorización de ARCA. Subí el archivo antes de confirmar.', 'imagen');
    perform fiscal.exigir_periodo_abierto(v_empresa.id, v_periodo, 'confirmar una compra imputada a ese mes');
  end if;

  if v_existente.id is null then
    insert into fiscal.comprobante (operacion, empresa_id, contraparte_id, tipo, punto_venta, numero, fecha, periodo, estado, creado_rol)
    values ('compra', v_empresa.id, v_prov.id, v_t.codigo, v_pv, v_numero, v_fecha, v_periodo, 'borrador', p_rol)
    returning id into v_id;
  end if;
  update fiscal.comprobante set
    contraparte_id = v_prov.id, tipo = v_t.codigo, punto_venta = v_pv, numero = v_numero, fecha = v_fecha, periodo = v_periodo,
    vencimiento_pago = nullif(p_datos->>'vencimiento_pago', '')::date, asociado_id = v_asoc.id, motivo = btrim(coalesce(p_datos->>'motivo', '')),
    condicion_venta = coalesce(p_datos->>'condicion_venta', ''), orden_compra = coalesce(p_datos->>'orden_compra', ''),
    presupuesto = coalesce(p_datos->>'presupuesto', ''), observaciones = coalesce(p_datos->>'observaciones', ''),
    cae = v_cae, vto_cae = nullif(p_datos->>'vto_cae', '')::date, imagen_path = v_imagen, imagen_nombre = nullif(p_datos->>'imagen_nombre', ''),
    contraparte_tipo_doc = v_prov.tipo_doc, contraparte_doc = v_prov.numero_doc, contraparte_razon = coalesce(v_prov.razon_social, v_prov.nombre),
    contraparte_condicion_iva = v_prov.condicion_iva, contraparte_domicilio = v_prov.domicilio,
    neto_gravado = (v_calc->'importes'->>'neto_gravado')::numeric, no_gravado = (v_calc->'importes'->>'no_gravado')::numeric,
    exento = (v_calc->'importes'->>'exento')::numeric, iva = (v_calc->'importes'->>'iva')::numeric,
    otros_tributos = (v_calc->'importes'->>'otros_tributos')::numeric, percepcion_iva = (v_calc->'importes'->>'percepcion_iva')::numeric,
    percepcion_iibb = (v_calc->'importes'->>'percepcion_iibb')::numeric, total = (v_calc->'importes'->>'total')::numeric
  where id = v_id;
  perform fiscal.guardar_detalle(v_id, '[]', v_calc->'desglose');
  select * into v_c from fiscal.comprobante where id = v_id;
  perform fiscal.registrar(p_rol, v_empresa.id, case when v_existente.id is null then 'cargó borrador' else 'modificó borrador' end, 'factura de compra',
    fiscal.etiqueta(v_c), format('%s · %s', v_c.contraparte_razon, fiscal.importe_texto(v_c.total)));
  if p_confirmar then
    update fiscal.comprobante set estado = 'confirmada', confirmado_en = now() where id = v_id returning * into v_c;
    perform fiscal.registrar(p_rol, v_empresa.id, 'confirmó', 'factura de compra', fiscal.etiqueta(v_c),
      format('%s · %s', v_c.contraparte_razon, fiscal.importe_texto(v_c.total)));
  end if;
  return fiscal.idem_guardar(p_clave, 'guardar_compra', p_datos || jsonb_build_object('confirmar', p_confirmar), fiscal.comprobante_json(v_id));
end $$;


do $$
declare f text;
begin
  foreach f in array array[
    'conciliar_arca(text, text, text, text, text, text)', 'importar_desde_arca(text, text, text, jsonb)',
    'confirmar_importadas(text, text)', 'archivo_ejemplo_arca(text, text, text)']
  loop
    execute format('revoke all on function public.%s from public', f);
    if exists (select 1 from pg_roles where rolname = 'anon') then
      execute format('grant execute on function public.%s to anon, authenticated', f);
    end if;
  end loop;
end $$;
