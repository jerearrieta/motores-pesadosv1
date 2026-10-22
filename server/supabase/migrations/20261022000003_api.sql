-- =====================================================================
-- API del prototipo: funciones RPC en el esquema public.
-- Es lo único que ve el front (supabase.rpc('nombre', {...})).
--   · Las que escriben son SECURITY DEFINER, validan rol y reglas, y
--     hacen todo en una sola transacción.
--   · El front nunca arma un número de comprobante ni calcula un IVA
--     para guardar: lo pide acá.
--   · Sin login en esta versión: el rol llega como parámetro (p_rol).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Libro de IVA (consulta interna)
-- ---------------------------------------------------------------------
create or replace function fiscal.libro_filas(p_empresa text, p_periodo text, p_operacion text)
returns table (
  id uuid, fecha date, tipo int, tipo_desc text, letra text, numero text, contraparte text, documento text, condicion text, estado text,
  n21 numeric, i21 numeric, n105 numeric, i105 numeric, n27 numeric, i27 numeric, n_otras numeric, i_otras numeric, n0 numeric,
  no_gravado numeric, exento numeric, otros_tributos numeric, perc_iva numeric, perc_iibb numeric, iva numeric, total numeric,
  neto numeric, no_gravado_exento numeric, moneda text, cotizacion numeric, cae text, imagen_path text
) language sql stable as $$
  with c as (
    select c.*, t.signo, t.descripcion as tdesc, t.letra as tletra
    from fiscal.comprobante c
    join fiscal.tipo_comprobante t on t.codigo = c.tipo
    where c.empresa_id = p_empresa and c.periodo = p_periodo and c.operacion = p_operacion
      and c.estado in (case when p_operacion = 'venta' then 'emitido_sin_cae' else 'confirmada' end, 'autorizado')
  ),
  d as (
    select ci.comprobante_id,
      sum(ci.base) filter (where a.porcentaje = 21) as n21, sum(ci.iva) filter (where a.porcentaje = 21) as i21,
      sum(ci.base) filter (where a.porcentaje = 10.5) as n105, sum(ci.iva) filter (where a.porcentaje = 10.5) as i105,
      sum(ci.base) filter (where a.porcentaje = 27) as n27, sum(ci.iva) filter (where a.porcentaje = 27) as i27,
      sum(ci.base) filter (where a.porcentaje not in (21, 10.5, 27, 0)) as n_otras, sum(ci.iva) filter (where a.porcentaje not in (21, 10.5, 27, 0)) as i_otras,
      sum(ci.base) filter (where a.porcentaje = 0) as n0
    from fiscal.comprobante_iva ci join fiscal.alicuota a on a.codigo = ci.alicuota_codigo
    where ci.comprobante_id in (select c.id from c)
    group by ci.comprobante_id
  ),
  -- a pesos (por si hay moneda extranjera) y con el signo del tipo: las notas de crédito restan
  x as (
    select c.*,
      c.signo * round(coalesce(d.n21, 0) * c.cotizacion, 2) as xn21, c.signo * round(coalesce(d.i21, 0) * c.cotizacion, 2) as xi21,
      c.signo * round(coalesce(d.n105, 0) * c.cotizacion, 2) as xn105, c.signo * round(coalesce(d.i105, 0) * c.cotizacion, 2) as xi105,
      c.signo * round(coalesce(d.n27, 0) * c.cotizacion, 2) as xn27, c.signo * round(coalesce(d.i27, 0) * c.cotizacion, 2) as xi27,
      c.signo * round(coalesce(d.n_otras, 0) * c.cotizacion, 2) as xn_otras, c.signo * round(coalesce(d.i_otras, 0) * c.cotizacion, 2) as xi_otras,
      c.signo * round(coalesce(d.n0, 0) * c.cotizacion, 2) as xn0,
      c.signo * round(c.no_gravado * c.cotizacion, 2) as xno_gravado, c.signo * round(c.exento * c.cotizacion, 2) as xexento,
      c.signo * round(c.otros_tributos * c.cotizacion, 2) as xotros, c.signo * round(c.percepcion_iva * c.cotizacion, 2) as xperc_iva,
      c.signo * round(c.percepcion_iibb * c.cotizacion, 2) as xperc_iibb
    from c left join d on d.comprobante_id = c.id
  )
  select x.id, x.fecha, x.tipo, x.tdesc, x.tletra::text, fiscal.numero_comprobante(x.punto_venta, x.numero), x.contraparte_razon,
    case when x.contraparte_tipo_doc = 99 then 'Sin identificar' else fiscal.formatear_cuit(x.contraparte_doc) end,
    coalesce((select ci.descripcion from fiscal.condicion_iva ci where ci.codigo = x.contraparte_condicion_iva), ''),
    x.estado,
    x.xn21, x.xi21, x.xn105, x.xi105, x.xn27, x.xi27, x.xn_otras, x.xi_otras, x.xn0,
    x.xno_gravado, x.xexento, x.xotros, x.xperc_iva, x.xperc_iibb,
    x.xi21 + x.xi105 + x.xi27 + x.xi_otras,
    x.xn21 + x.xn105 + x.xn27 + x.xn_otras + x.xn0 + x.xi21 + x.xi105 + x.xi27 + x.xi_otras + x.xno_gravado + x.xexento + x.xotros + x.xperc_iva + x.xperc_iibb,
    x.xn21 + x.xn105 + x.xn27 + x.xn_otras + x.xn0, x.xno_gravado + x.xexento,
    x.moneda, x.cotizacion, x.cae, x.imagen_path
  from x
  order by x.fecha, fiscal.numero_comprobante(x.punto_venta, x.numero)
$$;

create or replace function fiscal.libro_json(p_empresa text, p_periodo text, p_operacion text)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'filas', coalesce((select jsonb_agg(to_jsonb(f)) from fiscal.libro_filas(p_empresa, p_periodo, p_operacion) f), '[]'::jsonb),
    'totales', (select jsonb_build_object(
      'n21', coalesce(sum(n21), 0), 'i21', coalesce(sum(i21), 0), 'n105', coalesce(sum(n105), 0), 'i105', coalesce(sum(i105), 0),
      'n27', coalesce(sum(n27), 0), 'i27', coalesce(sum(i27), 0), 'n_otras', coalesce(sum(n_otras), 0), 'i_otras', coalesce(sum(i_otras), 0),
      'n0', coalesce(sum(n0), 0), 'no_gravado', coalesce(sum(no_gravado), 0), 'exento', coalesce(sum(exento), 0),
      'otros_tributos', coalesce(sum(otros_tributos), 0), 'perc_iva', coalesce(sum(perc_iva), 0), 'perc_iibb', coalesce(sum(perc_iibb), 0),
      'iva', coalesce(sum(iva), 0), 'total', coalesce(sum(total), 0), 'neto', coalesce(sum(neto), 0),
      'no_gravado_exento', coalesce(sum(no_gravado_exento), 0), 'cantidad', count(*))
      from fiscal.libro_filas(p_empresa, p_periodo, p_operacion)))
$$;

create or replace function fiscal.posicion(p_empresa text, p_periodo text)
returns jsonb language sql stable as $$
  with v as (select coalesce(sum(iva), 0) as iva, count(*) as n from fiscal.libro_filas(p_empresa, p_periodo, 'venta')),
       c as (select coalesce(sum(iva), 0) as iva, coalesce(sum(perc_iva), 0) as perc_iva, coalesce(sum(perc_iibb), 0) as perc_iibb, count(*) as n
             from fiscal.libro_filas(p_empresa, p_periodo, 'compra'))
  select jsonb_build_object('empresa_id', p_empresa, 'periodo', p_periodo, 'estado', fiscal.estado_periodo(p_empresa, p_periodo),
    'debito', v.iva, 'credito', c.iva, 'saldo', v.iva - c.iva, 'perc_iva', c.perc_iva, 'perc_iibb', c.perc_iibb,
    'ventas', v.n, 'compras', c.n)
  from v, c
$$;

-- Comprobante completo, para el detalle y para devolver después de guardar
create or replace function fiscal.comprobante_json(p_id uuid)
returns jsonb language sql stable as $$
  select to_jsonb(c) || jsonb_build_object(
    'tipo_desc', t.descripcion, 'letra', t.letra, 'clase', t.clase, 'discrimina_iva', t.discrimina_iva, 'signo', t.signo,
    'numero_texto', fiscal.numero_comprobante(c.punto_venta, c.numero),
    'etiqueta', t.descripcion || ' ' || fiscal.numero_comprobante(c.punto_venta, c.numero),
    'documento', case when c.contraparte_tipo_doc = 99 then 'Sin identificar' else fiscal.formatear_cuit(c.contraparte_doc) end,
    'condicion_desc', (select ci.descripcion from fiscal.condicion_iva ci where ci.codigo = c.contraparte_condicion_iva),
    'empresa', (select to_jsonb(e) from fiscal.empresa e where e.id = c.empresa_id),
    'items', coalesce((select jsonb_agg(to_jsonb(l) order by l.orden) from fiscal.comprobante_linea l where l.comprobante_id = c.id), '[]'::jsonb),
    'desglose', coalesce((select jsonb_agg(jsonb_build_object('alicuota_codigo', ci.alicuota_codigo, 'porcentaje', a.porcentaje, 'base', ci.base, 'iva', ci.iva) order by a.porcentaje desc)
                          from fiscal.comprobante_iva ci join fiscal.alicuota a on a.codigo = ci.alicuota_codigo where ci.comprobante_id = c.id), '[]'::jsonb),
    'asociado', (select jsonb_build_object('id', a.id, 'etiqueta', fiscal.etiqueta(a), 'total', a.total) from fiscal.comprobante a where a.id = c.asociado_id),
    'notas', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'etiqueta', fiscal.etiqueta(n), 'total', n.total, 'estado', n.estado, 'fecha', n.fecha) order by n.fecha)
                       from fiscal.comprobante n where n.asociado_id = c.id), '[]'::jsonb),
    'nc_disponible', case when t.clase = 'factura' then c.total - coalesce((
        select sum(n.total) from fiscal.comprobante n join fiscal.tipo_comprobante nt on nt.codigo = n.tipo
        where n.asociado_id = c.id and nt.clase = 'nota_credito' and n.estado not in ('borrador', 'anulada')), 0) end,
    'monto_en_letras', null)
  from fiscal.comprobante c join fiscal.tipo_comprobante t on t.codigo = c.tipo
  where c.id = p_id
$$;

-- Qué le falta a una contraparte para poder facturarle o cargarle una compra
create or replace function fiscal.faltantes(c fiscal.contraparte)
returns text[] language sql immutable as $$
  select array_remove(array[
    case when c.tipo_doc is null or coalesce(c.numero_doc, '') = '' then 'Sin CUIT o documento'
         when not fiscal.documento_valido(c.tipo_doc, c.numero_doc) then 'Documento inválido' end,
    case when coalesce(c.razon_social, '') = '' then 'Sin razón social' end,
    case when c.condicion_iva is null then 'Sin condición frente al IVA' end
  ], null)
$$;

-- ---------------------------------------------------------------------
-- Lecturas
-- ---------------------------------------------------------------------
create or replace function public.catalogos()
returns jsonb language sql stable security definer set search_path = fiscal, pg_temp as $$
  select jsonb_build_object(
    'empresas', (select jsonb_agg(to_jsonb(e) order by e.id) from fiscal.empresa e),
    'puntos_venta', (select jsonb_agg(to_jsonb(p) order by p.empresa_id, p.numero) from fiscal.punto_venta p),
    'tipos', (select jsonb_agg(to_jsonb(t) order by t.codigo) from fiscal.tipo_comprobante t),
    'condiciones', (select jsonb_agg(to_jsonb(c) order by c.codigo) from fiscal.condicion_iva c),
    'alicuotas', (select jsonb_agg(to_jsonb(a) order by a.porcentaje desc) from fiscal.alicuota a where a.soportada),
    'tipos_documento', (select jsonb_agg(to_jsonb(d) order by d.codigo) from fiscal.tipo_documento d),
    'roles', (select jsonb_agg(to_jsonb(r) order by r.id) from fiscal.rol r),
    'permisos', (select jsonb_object_agg(p.accion, p.roles) from (select accion, jsonb_agg(rol) as roles from fiscal.permiso group by accion) p))
$$;

create or replace function public.listar_contrapartes(p_tipo text default null)
returns jsonb language sql stable security definer set search_path = fiscal, pg_temp as $$
  select coalesce(jsonb_agg(to_jsonb(c) || jsonb_build_object(
      'documento', case when c.tipo_doc = 99 then 'Sin identificar' else fiscal.formatear_cuit(c.numero_doc) end,
      'condicion_desc', (select ci.descripcion from fiscal.condicion_iva ci where ci.codigo = c.condicion_iva),
      'faltantes', to_jsonb(fiscal.faltantes(c)),
      'completo', cardinality(fiscal.faltantes(c)) = 0
        and (not c.es_proveedor or p_tipo = 'cliente' or c.tipo_doc = 80))
    order by c.nombre), '[]'::jsonb)
  from fiscal.contraparte c
  where p_tipo is null or (p_tipo = 'cliente' and c.es_cliente) or (p_tipo = 'proveedor' and c.es_proveedor)
$$;

create or replace function public.listar_comprobantes(p_empresa text, p_operacion text, p_periodo text default null)
returns jsonb language sql stable security definer set search_path = fiscal, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'operacion', c.operacion, 'tipo', c.tipo, 'tipo_desc', t.descripcion, 'letra', t.letra, 'clase', t.clase,
      'numero_texto', fiscal.numero_comprobante(c.punto_venta, c.numero), 'fecha', c.fecha, 'periodo', c.periodo, 'estado', c.estado,
      'contraparte', c.contraparte_razon, 'documento', case when c.contraparte_tipo_doc = 99 then 'Sin identificar' else fiscal.formatear_cuit(c.contraparte_doc) end,
      'neto_gravado', c.neto_gravado, 'iva', c.iva, 'total', c.total, 'imagen_path', c.imagen_path, 'cae', c.cae,
      'asociado', (select fiscal.etiqueta(a) from fiscal.comprobante a where a.id = c.asociado_id),
      'motivo', c.motivo, 'motivo_anulacion', c.motivo_anulacion,
      'periodo_estado', fiscal.estado_periodo(c.empresa_id, c.periodo))
    order by c.fecha desc, c.creado_en desc), '[]'::jsonb)
  from fiscal.comprobante c join fiscal.tipo_comprobante t on t.codigo = c.tipo
  where c.empresa_id = p_empresa and c.operacion = p_operacion and (p_periodo is null or c.periodo = p_periodo)
$$;

create or replace function public.obtener_comprobante(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = fiscal, pg_temp as $$
declare r jsonb := fiscal.comprobante_json(p_id);
begin
  perform fiscal.req(r is not null, 'NO_ENCONTRADO', 'El comprobante no existe.');
  return r;
end $$;

create or replace function public.libro_iva(p_empresa text, p_periodo text, p_operacion text)
returns jsonb language plpgsql stable security definer set search_path = fiscal, pg_temp as $$
begin
  perform fiscal.req(p_operacion in ('venta', 'compra'), 'VALIDACION', 'El libro es de ventas o de compras.');
  return fiscal.libro_json(p_empresa, p_periodo, p_operacion);
end $$;

create or replace function public.posicion_iva(p_empresa text, p_periodo text)
returns jsonb language sql stable security definer set search_path = fiscal, pg_temp as $$
  select fiscal.posicion(p_empresa, p_periodo)
$$;

-- Períodos con movimientos (más el mes actual y los dos que lo rodean), con su posición
create or replace function public.periodos_iva(p_empresa text)
returns jsonb language sql stable security definer set search_path = fiscal, pg_temp as $$
  with p as (
    select periodo from fiscal.comprobante where empresa_id = p_empresa
    union select periodo from fiscal.periodo_iva where empresa_id = p_empresa
    union select to_char(current_date + make_interval(months => m), 'YYYY-MM') from generate_series(-1, 1) m
  )
  select coalesce(jsonb_agg(fiscal.posicion(p_empresa, p.periodo) order by p.periodo desc), '[]'::jsonb) from p
$$;

-- Lo que hay que mirar antes de cerrar un mes
create or replace function public.pendientes_cierre(p_empresa text, p_periodo text)
returns jsonb language sql stable security definer set search_path = fiscal, pg_temp as $$
  with items as (
    select 'bloquea' as nivel, 'Comprobantes cuyo IVA no coincide con el desglose por alícuota' as texto,
      (select count(*) from fiscal.comprobante c where c.empresa_id = p_empresa and c.periodo = p_periodo and c.estado not in ('borrador', 'anulada')
         and c.iva <> coalesce((select sum(ci.iva) from fiscal.comprobante_iva ci where ci.comprobante_id = c.id), 0)) as cantidad,
      'Hay que corregirlos antes de cerrar.' as ayuda
    union all
    select 'revisar', 'Facturas de venta en borrador con fecha del período: no entran al libro',
      (select count(*) from fiscal.comprobante c where c.empresa_id = p_empresa and c.periodo = p_periodo and c.operacion = 'venta' and c.estado = 'borrador'),
      'Emitilas o borralas.'
    union all
    select 'revisar', 'Facturas de compra en borrador imputadas al período: no suman crédito fiscal',
      (select count(*) from fiscal.comprobante c where c.empresa_id = p_empresa and c.periodo = p_periodo and c.operacion = 'compra' and c.estado = 'borrador'),
      'Completalas y confirmalas.'
    union all
    select 'revisar', 'Compras confirmadas sin imagen ni código de autorización',
      (select count(*) from fiscal.comprobante c where c.empresa_id = p_empresa and c.periodo = p_periodo and c.operacion = 'compra' and c.estado = 'confirmada'
         and c.imagen_path is null and c.cae = ''),
      'Adjuntá el respaldo.'
  )
  select jsonb_build_object(
    'items', jsonb_agg(jsonb_build_object('nivel', case when cantidad = 0 then 'ok' else nivel end, 'texto', texto, 'cantidad', cantidad,
                                          'ayuda', case when cantidad = 0 then '' else ayuda end)),
    'bloquea', bool_or(nivel = 'bloquea' and cantidad > 0),
    'revisar', count(*) filter (where nivel = 'revisar' and cantidad > 0),
    'estado', fiscal.estado_periodo(p_empresa, p_periodo))
  from items
$$;

-- Filas con las columnas de la hoja «Facturas» del Excel prototipo-libro-iva.xlsx
create or replace function public.exportar_facturas(p_empresa text, p_periodo text default null)
returns jsonb language sql stable security definer set search_path = fiscal, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'operacion', initcap(c.operacion), 'empresa', c.empresa_id, 'tipo_comprobante', t.descripcion, 'letra', t.letra,
      'punto_venta', c.punto_venta, 'numero', c.numero, 'fecha', c.fecha, 'periodo', c.periodo,
      'contraparte', c.contraparte_razon, 'cuit', c.contraparte_doc,
      'condicion_iva', (select ci.descripcion from fiscal.condicion_iva ci where ci.codigo = c.contraparte_condicion_iva),
      'condicion_venta', c.condicion_venta,
      'neto_21', coalesce((select sum(ci.base) from fiscal.comprobante_iva ci join fiscal.alicuota a on a.codigo = ci.alicuota_codigo where ci.comprobante_id = c.id and a.porcentaje = 21), 0),
      'neto_10_5', coalesce((select sum(ci.base) from fiscal.comprobante_iva ci join fiscal.alicuota a on a.codigo = ci.alicuota_codigo where ci.comprobante_id = c.id and a.porcentaje = 10.5), 0),
      'neto_27', coalesce((select sum(ci.base) from fiscal.comprobante_iva ci join fiscal.alicuota a on a.codigo = ci.alicuota_codigo where ci.comprobante_id = c.id and a.porcentaje = 27), 0),
      'no_gravado', c.no_gravado + c.exento + coalesce((select sum(ci.base) from fiscal.comprobante_iva ci join fiscal.alicuota a on a.codigo = ci.alicuota_codigo where ci.comprobante_id = c.id and a.porcentaje not in (21, 10.5, 27)), 0),
      'iva_21', coalesce((select sum(ci.iva) from fiscal.comprobante_iva ci join fiscal.alicuota a on a.codigo = ci.alicuota_codigo where ci.comprobante_id = c.id and a.porcentaje = 21), 0),
      'iva_10_5', coalesce((select sum(ci.iva) from fiscal.comprobante_iva ci join fiscal.alicuota a on a.codigo = ci.alicuota_codigo where ci.comprobante_id = c.id and a.porcentaje = 10.5), 0),
      'iva_27', coalesce((select sum(ci.iva) from fiscal.comprobante_iva ci join fiscal.alicuota a on a.codigo = ci.alicuota_codigo where ci.comprobante_id = c.id and a.porcentaje = 27), 0),
      'percepcion_iva', c.percepcion_iva, 'percepcion_iibb', c.percepcion_iibb, 'total', c.total,
      'cae', c.cae, 'vto_cae', c.vto_cae, 'imagen', coalesce(c.imagen_path, ''), 'presupuesto', c.presupuesto, 'orden_compra', c.orden_compra,
      'comprobante_asociado', coalesce((select fiscal.etiqueta(a) from fiscal.comprobante a where a.id = c.asociado_id), ''),
      'estado', case c.estado when 'borrador' then 'Borrador' when 'anulada' then 'Anulada' when 'emitido_sin_cae' then 'Emitida sin CAE' when 'autorizado' then 'Autorizada' else 'Registrada' end,
      'motivo_anulacion', c.motivo_anulacion)
    order by c.fecha, c.operacion desc, c.creado_en), '[]'::jsonb)
  from fiscal.comprobante c join fiscal.tipo_comprobante t on t.codigo = c.tipo
  where c.empresa_id = p_empresa and (p_periodo is null or c.periodo = p_periodo)
$$;

create or replace function public.ver_historial(p_rol text, p_empresa text default null)
returns jsonb language plpgsql stable security definer set search_path = fiscal, pg_temp as $$
begin
  perform fiscal.exigir(p_rol, 'ver_historial');
  return coalesce((select jsonb_agg(to_jsonb(h) || jsonb_build_object('rol_desc', r.descripcion) order by h.n desc)
                   from fiscal.historial h left join fiscal.rol r on r.id = h.rol
                   where p_empresa is null or h.empresa_id is null or h.empresa_id = p_empresa), '[]'::jsonb);
end $$;

-- Vista previa de importes mientras se carga: no guarda nada
create or replace function public.calcular_comprobante(p_datos jsonb)
returns jsonb language plpgsql stable security definer set search_path = fiscal, pg_temp as $$
declare v_op text := p_datos->>'operacion';
begin
  if v_op = 'venta' then
    return fiscal.calcular_venta(p_datos->'lineas', coalesce(p_datos->>'modo', 'neto'));
  elsif v_op = 'compra' then
    return fiscal.calcular_compra((p_datos->>'tipo')::int, p_datos->'desglose', p_datos);
  elsif v_op = 'nota' then
    return fiscal.calcular_compra(1, (select coalesce(jsonb_agg(jsonb_build_object('alicuota_codigo', l->'alicuota_codigo', 'base', l->'neto')), '[]')
                                      from jsonb_array_elements(coalesce(p_datos->'lineas', '[]')) l), '{}');
  end if;
  perform fiscal.error('VALIDACION', 'Operación desconocida.');
end $$;

-- ---------------------------------------------------------------------
-- Clientes y proveedores
-- ---------------------------------------------------------------------
create or replace function public.guardar_contraparte(p_rol text, p_datos jsonb)
returns jsonb language plpgsql security definer set search_path = fiscal, pg_temp as $$
declare
  v_id uuid := nullif(p_datos->>'id', '')::uuid;
  v_tipo text := p_datos->>'tipo';
  v_tipo_doc int := nullif(p_datos->>'tipo_doc', '')::int;
  v_doc text := regexp_replace(coalesce(p_datos->>'numero_doc', ''), '[\s.-]', '', 'g');
  v_razon text := btrim(coalesce(p_datos->>'razon_social', ''));
  v_nombre text := coalesce(nullif(btrim(p_datos->>'nombre'), ''), v_razon);
  v_cond int := nullif(p_datos->>'condicion_iva', '')::int;
  v_antes fiscal.contraparte;
  v_r fiscal.contraparte;
begin
  perform fiscal.exigir(p_rol, 'datos_fiscales');
  perform fiscal.req(v_tipo in ('cliente', 'proveedor'), 'VALIDACION', 'Indicá si es cliente o proveedor.');
  perform fiscal.req(v_nombre <> '', 'VALIDACION', 'Falta el nombre o la razón social.', 'razon_social');
  if v_tipo_doc = 99 then v_doc := '0'; end if;
  if v_tipo = 'proveedor' then
    perform fiscal.req(v_tipo_doc = 80, 'VALIDACION', 'Un proveedor se identifica con su CUIT.', 'tipo_doc');
  end if;
  if v_tipo_doc is not null then
    perform fiscal.req(v_tipo_doc in (select codigo from fiscal.tipo_documento), 'VALIDACION', 'Elegí el tipo de documento.', 'tipo_doc');
    if v_tipo_doc in (80, 86) then
      perform fiscal.req(fiscal.cuit_valido(v_doc), 'CUIT_INVALIDO', 'El CUIT tiene que tener 11 dígitos y un dígito verificador correcto.', 'numero_doc');
    elsif v_tipo_doc = 96 then
      perform fiscal.req(v_doc ~ '^\d{7,8}$', 'VALIDACION', 'Un DNI tiene 7 u 8 dígitos.', 'numero_doc');
    end if;
  end if;
  perform fiscal.req(v_razon <> '', 'VALIDACION', 'Falta la razón social.', 'razon_social');
  perform fiscal.req(v_cond in (select codigo from fiscal.condicion_iva), 'VALIDACION', 'Elegí la condición frente al IVA.', 'condicion_iva');

  if v_id is null then
    insert into fiscal.contraparte (codigo, nombre, es_cliente, es_proveedor, tipo_doc, numero_doc, razon_social, condicion_iva, domicilio, localidad, provincia, telefono, email, ingresos_brutos)
    values (coalesce(p_datos->>'codigo', ''), v_nombre, v_tipo = 'cliente', v_tipo = 'proveedor', v_tipo_doc, v_doc, v_razon, v_cond,
            coalesce(p_datos->>'domicilio', ''), coalesce(p_datos->>'localidad', ''), coalesce(p_datos->>'provincia', ''),
            coalesce(p_datos->>'telefono', ''), coalesce(p_datos->>'email', ''), coalesce(p_datos->>'ingresos_brutos', ''))
    returning * into v_r;
  else
    select * into v_antes from fiscal.contraparte where id = v_id;
    perform fiscal.req(v_antes.id is not null, 'NO_ENCONTRADO', 'La contraparte no existe.');
    update fiscal.contraparte set codigo = coalesce(p_datos->>'codigo', codigo), nombre = v_nombre, tipo_doc = v_tipo_doc, numero_doc = v_doc,
      razon_social = v_razon, condicion_iva = v_cond, domicilio = coalesce(p_datos->>'domicilio', ''), localidad = coalesce(p_datos->>'localidad', ''),
      provincia = coalesce(p_datos->>'provincia', ''), telefono = coalesce(p_datos->>'telefono', ''), email = coalesce(p_datos->>'email', ''),
      ingresos_brutos = coalesce(p_datos->>'ingresos_brutos', ''), actualizado_en = now(),
      es_cliente = es_cliente or v_tipo = 'cliente', es_proveedor = es_proveedor or v_tipo = 'proveedor'
    where id = v_id returning * into v_r;
  end if;
  perform fiscal.registrar(p_rol, null, case when v_id is null then 'creó' else 'modificó' end,
    'datos fiscales del ' || v_tipo, v_r.nombre,
    (select descripcion from fiscal.tipo_documento where codigo = v_r.tipo_doc) || ' ' || fiscal.formatear_cuit(v_r.numero_doc) || ' · ' ||
    (select descripcion from fiscal.condicion_iva where codigo = v_r.condicion_iva));
  return to_jsonb(v_r);
end $$;

-- ---------------------------------------------------------------------
-- Facturas de venta
-- ---------------------------------------------------------------------
create or replace function public.guardar_venta(p_rol text, p_datos jsonb, p_emitir boolean default false, p_clave uuid default null)
returns jsonb language plpgsql security definer set search_path = fiscal, pg_temp as $$
declare
  v_prev jsonb := fiscal.idem_buscar(p_clave, 'guardar_venta', p_datos || jsonb_build_object('emitir', p_emitir));
  v_id uuid := nullif(p_datos->>'id', '')::uuid;
  v_empresa fiscal.empresa;
  v_cli fiscal.contraparte;
  v_existente fiscal.comprobante;
  v_pv int := nullif(p_datos->>'punto_venta', '')::int;
  v_fecha date;
  v_modo text := coalesce(nullif(p_datos->>'modo', ''), 'neto');
  v_calc jsonb;
  v_letra char(1);
  v_tipo int;
  v_numero int;
  v_c fiscal.comprobante;
begin
  if v_prev is not null then return v_prev; end if;
  perform fiscal.exigir(p_rol, 'emitir_venta');
  select * into v_empresa from fiscal.empresa where id = p_datos->>'empresa_id';
  perform fiscal.req(v_empresa.id is not null, 'NO_ENCONTRADO', 'La empresa no existe.');
  select * into v_cli from fiscal.contraparte where id = nullif(p_datos->>'contraparte_id', '')::uuid and es_cliente;
  perform fiscal.req(v_cli.id is not null, 'VALIDACION', 'Elegí un cliente.', 'contraparte_id');
  if v_id is not null then
    select * into v_existente from fiscal.comprobante where id = v_id and operacion = 'venta';
    perform fiscal.req(v_existente.id is not null, 'NO_ENCONTRADO', 'El comprobante no existe.');
    perform fiscal.req(v_existente.estado = 'borrador', 'COMPROBANTE_INMUTABLE',
      format('%s ya fue emitida y no se puede editar. Se corrige con una nota de crédito o de débito.', fiscal.etiqueta(v_existente)));
  end if;
  perform fiscal.req(exists (select 1 from fiscal.punto_venta where empresa_id = v_empresa.id and numero = v_pv), 'EMPRESA_DISTINTA',
    'Elegí un punto de venta de la misma empresa.', 'punto_venta');
  begin v_fecha := (p_datos->>'fecha')::date; exception when others then v_fecha := null; end;
  perform fiscal.req(v_fecha is not null, 'VALIDACION', 'Falta la fecha de emisión.', 'fecha');

  v_calc := fiscal.calcular_venta(p_datos->'lineas', v_modo);
  select letra_venta into v_letra from fiscal.condicion_iva where codigo = v_cli.condicion_iva;

  if p_emitir then
    perform fiscal.req(cardinality(fiscal.faltantes(v_cli)) = 0, 'DATOS_FISCALES_INCOMPLETOS',
      format('El cliente «%s» no tiene datos fiscales completos (%s). Completalos en Clientes.', v_cli.nombre, array_to_string(fiscal.faltantes(v_cli), ', ')), 'contraparte_id');
    perform fiscal.req(v_letra is not null, 'TIPO_INVALIDO',
      format('La condición «%s» todavía no tiene una letra de factura definida. Consultalo con el contador.', (select descripcion from fiscal.condicion_iva where codigo = v_cli.condicion_iva)), 'contraparte_id');
    perform fiscal.exigir_periodo_abierto(v_empresa.id, to_char(v_fecha, 'YYYY-MM'), 'emitir con fecha de ese mes');
    -- RG 5866: desde $ 10.000.000 hay que identificar al consumidor final
    perform fiscal.req(not (v_letra = 'B' and v_cli.tipo_doc = 99 and (v_calc->'importes'->>'total')::numeric >= 10000000), 'DATOS_FISCALES_INCOMPLETOS',
      'Desde $ 10.000.000,00 hay que identificar al consumidor final con CUIT, CUIL o DNI (RG 5866).', 'contraparte_id');
  end if;
  v_tipo := case coalesce(v_letra, 'A') when 'A' then 1 else 6 end;

  if v_existente.id is null then
    insert into fiscal.comprobante (operacion, empresa_id, contraparte_id, tipo, punto_venta, fecha, periodo, estado, modo, creado_rol)
    values ('venta', v_empresa.id, v_cli.id, v_tipo, v_pv, v_fecha, to_char(v_fecha, 'YYYY-MM'), 'borrador', v_modo, p_rol)
    returning id into v_id;
  end if;
  update fiscal.comprobante set
    contraparte_id = v_cli.id, tipo = v_tipo, punto_venta = v_pv, fecha = v_fecha, periodo = to_char(v_fecha, 'YYYY-MM'), modo = v_modo,
    condicion_venta = coalesce(p_datos->>'condicion_venta', ''), orden_compra = coalesce(p_datos->>'orden_compra', ''),
    remito = coalesce(p_datos->>'remito', ''), presupuesto = coalesce(p_datos->>'presupuesto', ''), observaciones = coalesce(p_datos->>'observaciones', ''),
    vencimiento_pago = nullif(p_datos->>'vencimiento_pago', '')::date,
    contraparte_tipo_doc = v_cli.tipo_doc, contraparte_doc = v_cli.numero_doc, contraparte_razon = coalesce(v_cli.razon_social, v_cli.nombre),
    contraparte_condicion_iva = v_cli.condicion_iva, contraparte_domicilio = concat_ws(', ', nullif(v_cli.domicilio, ''), nullif(v_cli.localidad, ''), nullif(v_cli.provincia, '')),
    neto_gravado = (v_calc->'importes'->>'neto_gravado')::numeric, no_gravado = 0, exento = 0, otros_tributos = 0, percepcion_iva = 0, percepcion_iibb = 0,
    iva = (v_calc->'importes'->>'iva')::numeric, total = (v_calc->'importes'->>'total')::numeric
  where id = v_id;
  perform fiscal.guardar_detalle(v_id, v_calc->'items', v_calc->'desglose');
  select * into v_c from fiscal.comprobante where id = v_id;
  perform fiscal.registrar(p_rol, v_empresa.id, case when v_existente.id is null then 'creó borrador' else 'modificó borrador' end, 'factura de venta',
    fiscal.etiqueta(v_c), format('%s · %s', v_c.contraparte_razon, fiscal.importe_texto(v_c.total)));

  if p_emitir then
    v_numero := fiscal.siguiente_numero(v_empresa.id, v_pv, v_tipo);
    update fiscal.comprobante set numero = v_numero, estado = 'emitido_sin_cae', emitido_en = now() where id = v_id returning * into v_c;
    perform fiscal.registrar(p_rol, v_empresa.id, 'emitió sin CAE', 'factura de venta', fiscal.etiqueta(v_c),
      format('%s · %s', v_c.contraparte_razon, fiscal.importe_texto(v_c.total)));
  end if;
  return fiscal.idem_guardar(p_clave, 'guardar_venta', p_datos || jsonb_build_object('emitir', p_emitir), fiscal.comprobante_json(v_id));
end $$;

-- Notas de crédito y de débito sobre una factura emitida
create or replace function public.emitir_nota_venta(p_rol text, p_datos jsonb, p_clave uuid default null)
returns jsonb language plpgsql security definer set search_path = fiscal, pg_temp as $$
declare
  v_prev jsonb := fiscal.idem_buscar(p_clave, 'emitir_nota_venta', p_datos);
  v_fa fiscal.comprobante;
  v_tfa fiscal.tipo_comprobante;
  v_clase text := p_datos->>'clase';
  v_motivo text := btrim(coalesce(p_datos->>'motivo', ''));
  v_fecha date;
  v_calc jsonb;
  v_disponible numeric;
  v_tipo int;
  v_id uuid;
  v_c fiscal.comprobante;
begin
  if v_prev is not null then return v_prev; end if;
  perform fiscal.exigir(p_rol, 'emitir_nota_venta');
  select * into v_fa from fiscal.comprobante where id = nullif(p_datos->>'factura_id', '')::uuid and operacion = 'venta';
  perform fiscal.req(v_fa.id is not null, 'NOTA_SIN_ASOCIADO', 'La nota tiene que apuntar a una factura.');
  select * into v_tfa from fiscal.tipo_comprobante where codigo = v_fa.tipo;
  perform fiscal.req(v_fa.estado <> 'borrador', 'ASOCIADO_BORRADOR', 'La nota apunta a un borrador. Emití primero la factura.');
  perform fiscal.req(v_tfa.clase = 'factura', 'TIPO_INVALIDO', 'Las notas se asocian a una factura, no a otra nota.');
  perform fiscal.req(v_clase in ('credito', 'debito'), 'VALIDACION', 'Elegí si es nota de crédito o de débito.');
  perform fiscal.req(v_motivo <> '', 'MOTIVO_OBLIGATORIO', 'Toda nota exige un motivo.', 'motivo');
  begin v_fecha := (p_datos->>'fecha')::date; exception when others then v_fecha := null; end;
  perform fiscal.req(v_fecha is not null, 'VALIDACION', 'Falta la fecha.', 'fecha');
  perform fiscal.req(v_fecha >= v_fa.fecha, 'VALIDACION', 'La nota no puede tener fecha anterior a la factura.', 'fecha');
  perform fiscal.exigir_periodo_abierto(v_fa.empresa_id, to_char(v_fecha, 'YYYY-MM'), 'emitir con fecha de ese mes');

  v_calc := fiscal.calcular_compra(1, (select coalesce(jsonb_agg(jsonb_build_object('alicuota_codigo', l->'alicuota_codigo', 'base', l->'neto')), '[]')
                                       from jsonb_array_elements(coalesce(p_datos->'lineas', '[]')) l));
  perform fiscal.req((v_calc->'importes'->>'total')::numeric > 0, 'VALIDACION', 'Escribí al menos un importe neto mayor que cero.', 'lineas');
  if v_clase = 'credito' then
    v_disponible := (fiscal.comprobante_json(v_fa.id)->>'nc_disponible')::numeric;
    perform fiscal.req((v_calc->'importes'->>'total')::numeric <= v_disponible, 'TOTALES_INCONSISTENTES',
      format('Las notas de crédito de una factura no pueden superar su total. Disponible: %s; esta nota: %s.',
             fiscal.importe_texto(v_disponible), fiscal.importe_texto((v_calc->'importes'->>'total')::numeric)), 'lineas');
  end if;
  v_tipo := case v_tfa.letra when 'A' then case v_clase when 'credito' then 3 else 2 end else case v_clase when 'credito' then 8 else 7 end end;

  insert into fiscal.comprobante (operacion, empresa_id, contraparte_id, tipo, punto_venta, fecha, periodo, estado, asociado_id, motivo,
    condicion_venta, presupuesto, orden_compra, contraparte_tipo_doc, contraparte_doc, contraparte_razon, contraparte_condicion_iva, contraparte_domicilio,
    moneda, cotizacion, neto_gravado, iva, total, creado_rol)
  values ('venta', v_fa.empresa_id, v_fa.contraparte_id, v_tipo, v_fa.punto_venta, v_fecha, to_char(v_fecha, 'YYYY-MM'), 'borrador', v_fa.id, v_motivo,
    v_fa.condicion_venta, v_fa.presupuesto, v_fa.orden_compra, v_fa.contraparte_tipo_doc, v_fa.contraparte_doc, v_fa.contraparte_razon, v_fa.contraparte_condicion_iva,
    v_fa.contraparte_domicilio, v_fa.moneda, v_fa.cotizacion,
    (v_calc->'importes'->>'neto_gravado')::numeric, (v_calc->'importes'->>'iva')::numeric, (v_calc->'importes'->>'total')::numeric, p_rol)
  returning id into v_id;
  perform fiscal.guardar_detalle(v_id,
    (select jsonb_agg(jsonb_build_object('orden', o, 'codigo', '', 'descripcion', v_motivo, 'cantidad', 1, 'precio_lista', d->'base', 'descuento', 0,
                                         'precio_unitario', d->'base', 'alicuota_codigo', d->'alicuota_codigo', 'importe_neto', d->'base'))
     from jsonb_array_elements(v_calc->'desglose') with ordinality as x(d, o)),
    v_calc->'desglose');
  update fiscal.comprobante set numero = fiscal.siguiente_numero(v_fa.empresa_id, v_fa.punto_venta, v_tipo), estado = 'emitido_sin_cae', emitido_en = now()
  where id = v_id returning * into v_c;
  perform fiscal.registrar(p_rol, v_c.empresa_id, 'emitió sin CAE', 'nota de ' || case v_clase when 'credito' then 'crédito' else 'débito' end,
    fiscal.etiqueta(v_c), format('Sobre %s · %s · %s', fiscal.etiqueta(v_fa), v_motivo, fiscal.importe_texto(v_c.total)));
  return fiscal.idem_guardar(p_clave, 'emitir_nota_venta', p_datos, fiscal.comprobante_json(v_id));
end $$;

-- ---------------------------------------------------------------------
-- Facturas de compra
-- ---------------------------------------------------------------------
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
    perform fiscal.req(v_imagen is not null or v_cae <> '', 'ADJUNTO_OBLIGATORIO',
      'Falta la imagen o el PDF de la factura, o su CAE. Subí el archivo antes de confirmar.', 'imagen');
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

create or replace function public.anular_compra(p_rol text, p_id uuid, p_motivo text)
returns jsonb language plpgsql security definer set search_path = fiscal, pg_temp as $$
declare v_c fiscal.comprobante;
begin
  perform fiscal.exigir(p_rol, 'anular_compra');
  select * into v_c from fiscal.comprobante where id = p_id and operacion = 'compra' for update;
  perform fiscal.req(v_c.id is not null, 'NO_ENCONTRADO', 'El comprobante no existe.');
  perform fiscal.req(v_c.estado = 'confirmada', 'ESTADO_INVALIDO', 'Solo se anulan compras confirmadas.');
  perform fiscal.req(btrim(coalesce(p_motivo, '')) <> '', 'MOTIVO_OBLIGATORIO', 'Anular una compra exige un motivo.', 'motivo');
  perform fiscal.exigir_periodo_abierto(v_c.empresa_id, v_c.periodo, 'anular una compra imputada a ese mes');
  update fiscal.comprobante set estado = 'anulada', motivo_anulacion = btrim(p_motivo), anulado_en = now(), anulado_rol = p_rol where id = p_id;
  perform fiscal.registrar(p_rol, v_c.empresa_id, 'anuló', 'factura de compra', fiscal.etiqueta(v_c), btrim(p_motivo));
  return fiscal.comprobante_json(p_id);
end $$;

create or replace function public.eliminar_borrador(p_rol text, p_id uuid)
returns void language plpgsql security definer set search_path = fiscal, pg_temp as $$
declare v_c fiscal.comprobante;
begin
  select * into v_c from fiscal.comprobante where id = p_id;
  perform fiscal.req(v_c.id is not null, 'NO_ENCONTRADO', 'El comprobante no existe.');
  perform fiscal.exigir(p_rol, case v_c.operacion when 'venta' then 'emitir_venta' else 'cargar_compra' end);
  perform fiscal.req(v_c.estado = 'borrador', 'COMPROBANTE_INMUTABLE',
    format('%s ya fue emitido o confirmado y no se puede borrar.', fiscal.etiqueta(v_c)));
  delete from fiscal.comprobante where id = p_id;
  perform fiscal.registrar(p_rol, v_c.empresa_id, 'borró borrador', 'factura de ' || v_c.operacion, fiscal.etiqueta(v_c), v_c.contraparte_razon);
end $$;

-- ---------------------------------------------------------------------
-- Cierre de período
-- ---------------------------------------------------------------------
create or replace function public.cerrar_periodo(p_rol text, p_empresa text, p_periodo text)
returns jsonb language plpgsql security definer set search_path = fiscal, pg_temp as $$
begin
  perform fiscal.exigir(p_rol, 'cerrar_periodo');
  perform fiscal.req(exists (select 1 from fiscal.empresa where id = p_empresa), 'NO_ENCONTRADO', 'La empresa no existe.');
  perform fiscal.req(p_periodo ~ '^\d{4}-(0[1-9]|1[0-2])$', 'VALIDACION', 'El período no es válido.');
  perform fiscal.req(fiscal.estado_periodo(p_empresa, p_periodo) = 'abierto', 'ESTADO_INVALIDO', format('El período %s ya está cerrado.', p_periodo));
  perform fiscal.req(not (public.pendientes_cierre(p_empresa, p_periodo)->>'bloquea')::boolean, 'ESTADO_INVALIDO',
    'Hay controles del libro que no cierran. Corregilos antes de cerrar.');
  insert into fiscal.periodo_iva (empresa_id, periodo, estado, cerrado_rol, cerrado_en) values (p_empresa, p_periodo, 'cerrado', p_rol, now())
  on conflict (empresa_id, periodo) do update set estado = 'cerrado', cerrado_rol = p_rol, cerrado_en = now();
  perform fiscal.registrar(p_rol, p_empresa, 'cerró período', 'período de IVA', p_periodo,
    (select razon_social from fiscal.empresa where id = p_empresa));
  return fiscal.posicion(p_empresa, p_periodo);
end $$;

-- ---------------------------------------------------------------------
-- Permisos: el front (anon) solo puede ejecutar estas funciones
-- ---------------------------------------------------------------------
revoke all on all functions in schema fiscal from public;

do $$
declare f text;
begin
  foreach f in array array[
    'catalogos()', 'listar_contrapartes(text)', 'listar_comprobantes(text, text, text)', 'obtener_comprobante(uuid)',
    'libro_iva(text, text, text)', 'posicion_iva(text, text)', 'periodos_iva(text)', 'pendientes_cierre(text, text)',
    'exportar_facturas(text, text)', 'ver_historial(text, text)', 'calcular_comprobante(jsonb)',
    'guardar_contraparte(text, jsonb)', 'guardar_venta(text, jsonb, boolean, uuid)', 'emitir_nota_venta(text, jsonb, uuid)',
    'guardar_compra(text, jsonb, boolean, uuid)', 'anular_compra(text, uuid, text)', 'eliminar_borrador(text, uuid)',
    'cerrar_periodo(text, text, text)']
  loop
    execute format('revoke all on function public.%s from public', f);
    if exists (select 1 from pg_roles where rolname = 'anon') then
      execute format('grant execute on function public.%s to anon, authenticated', f);
    end if;
  end loop;
end $$;
