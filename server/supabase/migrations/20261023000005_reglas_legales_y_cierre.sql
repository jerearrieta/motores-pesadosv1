-- =====================================================================
-- Reglas legales y cierre (Simulador Libro de IVA):
-- - Factura B con el IVA incluido en las líneas (lineasConIvaIncluido):
--   el centavo de redondeo va a la última línea.
-- - Lista de cierre (pendientesCierre): controles del libro, borradores,
--   respaldo de compras, diferencias de precio sin aprobar, presupuestos
--   de venta entregados sin facturar, conciliación con ARCA de ventas y de
--   compras, y órdenes de compra recibidas sin factura (informativo).
-- - Clientes por prioridad (clientesPorPrioridad, US-021).
-- =====================================================================

-- Líneas de una factura B con el IVA incluido: precio de lista, precio unitario y total de cada línea
create or replace function fiscal.lineas_con_iva_incluido(p_id uuid)
returns jsonb language plpgsql stable as $$
declare
  v_total numeric;
  v_filas jsonb;
  v_suma numeric;
  v_n int;
  v_dif numeric;
begin
  select total into v_total from fiscal.comprobante where id = p_id;
  select coalesce(jsonb_agg(jsonb_build_object(
      'orden', l.orden,
      'lista', round(l.precio_lista, 2) + fiscal.calcular_iva(round(l.precio_lista, 2), a.porcentaje),
      'unitario', round(l.precio_unitario, 2) + fiscal.calcular_iva(round(l.precio_unitario, 2), a.porcentaje),
      'total', l.importe_neto + fiscal.calcular_iva(l.importe_neto, a.porcentaje)) order by l.orden), '[]'), count(*)
  into v_filas, v_n
  from fiscal.comprobante_linea l join fiscal.alicuota a on a.codigo = l.alicuota_codigo where l.comprobante_id = p_id;
  select coalesce(sum((x->>'total')::numeric), 0) into v_suma from jsonb_array_elements(v_filas) x;
  v_dif := v_total - v_suma;
  if v_n > 0 and v_dif <> 0 and abs(v_dif) * 100 <= v_n then
    v_filas := jsonb_set(v_filas, array[(v_n - 1)::text, 'total'], to_jsonb((v_filas->(v_n - 1)->>'total')::numeric + v_dif));
  end if;
  return v_filas;
end $$;

-- Lista de cierre del período
create or replace function public.pendientes_cierre(p_empresa text, p_periodo text)
returns jsonb language sql stable security definer set search_path = fiscal, pg_temp as $$
  with conc as (
    select t.o, t.tipo, k.cuando, k.resumen from (values (7, 'emitidos'), (8, 'recibidos')) t(o, tipo)
    left join fiscal.conciliacion_arca k on k.empresa_id = p_empresa and k.periodo = p_periodo and k.tipo_archivo = t.tipo
  ),
  oc as (select * from jsonb_array_elements(public.bandeja_compras(p_empresa)->'ordenes_sin_factura')),
  items as (
    select 1 as o, 'bloquea' as nivel, 'Controles del libro que no cierran (cada fila suma el total y el IVA coincide con el desglose por alícuota)' as texto,
      (select count(*) from fiscal.comprobante c where c.empresa_id = p_empresa and c.periodo = p_periodo and c.estado not in ('borrador', 'anulada')
         and (c.iva <> coalesce((select sum(ci.iva) from fiscal.comprobante_iva ci where ci.comprobante_id = c.id), 0)
              or c.total <> c.neto_gravado + c.no_gravado + c.exento + c.iva + c.otros_tributos + c.percepcion_iva + c.percepcion_iibb)) as cantidad,
      'Hay que corregirlos antes de cerrar.' as ayuda, '' as ayuda_ok
    union all
    select 2, 'revisar', 'Facturas de venta en borrador con fecha del período: no entran al libro',
      (select count(*) from fiscal.comprobante c where c.empresa_id = p_empresa and c.periodo = p_periodo and c.operacion = 'venta' and c.estado = 'borrador'),
      'Emitilas o borralas.', ''
    union all
    select 3, 'revisar', 'Facturas de compra en borrador imputadas al período: no suman crédito fiscal',
      (select count(*) from fiscal.comprobante c where c.empresa_id = p_empresa and c.periodo = p_periodo and c.operacion = 'compra' and c.estado = 'borrador'),
      'Completalas y confirmalas.', ''
    union all
    select 4, 'revisar', 'Compras confirmadas sin imagen ni código de autorización',
      (select count(*) from fiscal.comprobante c where c.empresa_id = p_empresa and c.periodo = p_periodo and c.operacion = 'compra' and c.estado = 'confirmada'
         and c.imagen_path is null and c.cae = '' and c.codigo_autorizacion = ''),
      'Adjuntá el respaldo.', ''
    union all
    select 5, 'revisar', 'Compras con diferencia de precio contra la orden de compra sin aprobar',
      (select count(*) from fiscal.revision_precio r join fiscal.comprobante c on c.id = r.comprobante_id
       where c.empresa_id = p_empresa and c.periodo = p_periodo and c.estado = 'confirmada' and r.aprobada_en is null),
      'Las aprueba Contador o Gerencia.', ''
    union all
    select 6, 'revisar', 'Presupuestos de venta entregados con líneas sin facturar (RG 5866: los repuestos se facturan hasta fin del mes de la entrega)',
      (select count(*) from fiscal.presupuesto p where p.empresa_id = p_empresa and p.estado = 'entregado'
         and exists (select 1 from fiscal.presupuesto_linea l where l.presupuesto_id = p.id
                     and not exists (select 1 from fiscal.comprobante_linea cl where cl.presupuesto_linea_id = l.id))),
      'Facturalos antes de fin de mes.', ''
    union all
    select conc.o, 'revisar', format('Conciliación con ARCA de %s', case when conc.tipo = 'emitidos' then 'ventas (Mis Comprobantes Emitidos)' else 'compras (Mis Comprobantes Recibidos)' end),
      case when conc.cuando is null then 1 else 0 end,
      'Recomendada antes de liquidar en IVA Simple.',
      case when conc.cuando is null then '' else format('Hecha el %s: %s con diferencia y %s que faltaban en el sistema. Si después cargaste o importaste algo, volvé a conciliar.', to_char(conc.cuando, 'DD/MM/YYYY'), conc.resumen->>'difiere', conc.resumen->>'falta_sistema') end
    from conc
    union all
    select 9, 'info', 'Órdenes de compra recibidas sin factura (deuda con proveedores sin documentar)', (select count(*) from oc),
      format('%s sin factura. No impide cerrar el IVA.', fiscal.importe_texto(coalesce((select sum((value->>'saldo')::numeric) from oc), 0))), ''
  )
  select jsonb_build_object(
    'items', jsonb_agg(jsonb_build_object('nivel', case when cantidad = 0 then 'ok' else nivel end, 'texto', texto, 'cantidad', cantidad,
                                          'ayuda', case when cantidad = 0 then ayuda_ok else ayuda end) order by o),
    'bloquea', bool_or(nivel = 'bloquea' and cantidad > 0),
    'revisar', count(*) filter (where nivel = 'revisar' and cantidad > 0),
    'estado', fiscal.estado_periodo(p_empresa, p_periodo))
  from items
$$;

-- Clientes ordenados por importancia: primero los que tienen datos incompletos, después los de más monto en presupuestos
-- de venta vigentes (en pesos; los presupuestos en dólares, con su cotización). Con p_empresa, solo los de esa empresa.
create or replace function public.clientes_por_prioridad(p_empresa text default null)
returns jsonb language sql stable security definer set search_path = fiscal, pg_temp as $$
  with pres as (
    select p.contraparte_id, p.empresa_id,
      round((fiscal.calcular_venta((select jsonb_agg(jsonb_build_object('descripcion', l.descripcion, 'cantidad', l.cantidad::text, 'precio', l.precio::text,
          'descuento', l.descuento::text, 'alicuota_codigo', l.alicuota_codigo) order by l.orden) from fiscal.presupuesto_linea l where l.presupuesto_id = p.id), 'neto')
        ->'importes'->>'total')::numeric * case when p.moneda = 'USD' then p.cotizacion else 1 end, 2) as total
    from fiscal.presupuesto p
    where p.estado not in ('cancelado', 'perdido') and (p_empresa is null or p.empresa_id = p_empresa)
  ),
  x as (
    select c.id, c.nombre, cardinality(fiscal.faltantes(c)) = 0 as completo, to_jsonb(fiscal.faltantes(c)) as faltantes,
      count(pres.total) as presupuestos, coalesce(sum(pres.total), 0) as monto,
      coalesce(jsonb_agg(distinct pres.empresa_id) filter (where pres.empresa_id is not null), '[]') as empresas
    from fiscal.contraparte c left join pres on pres.contraparte_id = c.id
    where c.es_cliente
    group by c.id
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre, 'completo', completo, 'faltantes', faltantes, 'presupuestos', presupuestos,
      'monto', monto, 'empresas', empresas, 'activo', presupuestos > 0) order by completo, monto desc, nombre), '[]')
  from x
$$;

-- comprobante_json: agrega las líneas con IVA incluido de la factura B
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
    'monto_en_letras', null,
    'ordenes', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'numero', o.numero, 'presupuesto', o.presupuesto, 'importe', o.importe) order by co.posicion)
                         from fiscal.compra_orden co join fiscal.orden_compra o on o.id = co.orden_id where co.comprobante_id = c.id), '[]'::jsonb),
    'revision_precio', (select to_jsonb(r) - 'comprobante_id' from fiscal.revision_precio r where r.comprobante_id = c.id),
    -- Factura B: las líneas van con el IVA incluido (el comprobante no discrimina IVA)
    'lineas_iva_incluido', case when c.operacion = 'venta' and t.letra = 'B' then fiscal.lineas_con_iva_incluido(c.id) end)
  from fiscal.comprobante c join fiscal.tipo_comprobante t on t.codigo = c.tipo
  where c.id = p_id
$$;


do $$
begin
  revoke all on function public.clientes_por_prioridad(text) from public;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant execute on function public.clientes_por_prioridad(text) to anon, authenticated;
  end if;
end $$;
