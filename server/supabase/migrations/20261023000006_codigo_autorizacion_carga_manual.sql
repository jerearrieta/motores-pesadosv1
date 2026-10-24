-- Carga a mano desde la conciliación con ARCA: la compra guarda el código de autorización que trae «Mis Comprobantes»
-- (por ejemplo FICTICIO-000008 en el ejemplo) y ese código cuenta como respaldo para confirmar, igual que al importar.
-- Es la misma función de la migración 20261023000003 con dos cambios, marcados con «código de autorización de ARCA».

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
  v_ordenes uuid[];
  v_categoria text := btrim(coalesce(p_datos->>'categoria', ''));
  v_jur text := btrim(coalesce(p_datos->>'jurisdiccion_iibb', ''));
  v_ctl jsonb;
  v_oc fiscal.orden_compra;
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

  -- Órdenes de compra que cubre la factura (US-061): de la misma empresa y del mismo proveedor
  begin
    v_ordenes := coalesce((select array_agg(x::uuid order by o) from jsonb_array_elements_text(coalesce(p_datos->'ordenes_compra', '[]')) with ordinality e(x, o)), '{}');
  exception when others then
    perform fiscal.error('VALIDACION', 'La orden de compra no existe.', 'ordenes_compra');
  end;
  perform fiscal.req(cardinality(v_ordenes) = (select count(*) from fiscal.orden_compra where id = any(v_ordenes)), 'VALIDACION', 'La orden de compra no existe.', 'ordenes_compra');
  for v_oc in select * from fiscal.orden_compra where id = any(v_ordenes) loop
    perform fiscal.req(v_oc.empresa_id = v_empresa.id, 'EMPRESA_DISTINTA', format('La orden %s es de la otra empresa.', v_oc.numero), 'ordenes_compra');
    perform fiscal.req(v_oc.proveedor_id = v_prov.id, 'VALIDACION', format('La orden %s es de otro proveedor.', v_oc.numero), 'ordenes_compra');
  end loop;
  perform fiscal.req(v_categoria = '' or exists (select 1 from fiscal.categoria_gasto where nombre = v_categoria), 'VALIDACION', 'La categoría de gasto no es válida.', 'categoria');
  perform fiscal.req(v_jur = '' or exists (select 1 from fiscal.jurisdiccion where nombre = v_jur), 'VALIDACION', 'La jurisdicción de Ingresos Brutos no es válida.', 'jurisdiccion_iibb');

  if p_confirmar then
    if v_t.clase = 'factura' then
      perform fiscal.req(cardinality(v_ordenes) > 0 or v_categoria <> '', 'VALIDACION',
        'Elegí las órdenes de compra que cubre esta factura o, si no hubo orden, una categoría de gasto.', 'categoria');
    end if;
    perform fiscal.req(v_imagen is not null or v_cae <> '' or coalesce(nullif(btrim(p_datos->>'codigo_autorizacion'), ''), v_existente.codigo_autorizacion, '') <> '', 'ADJUNTO_OBLIGATORIO',   -- código de autorización de ARCA
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
    condicion_venta = coalesce(p_datos->>'condicion_venta', ''), orden_compra = case when cardinality(v_ordenes) > 0 then (select string_agg(o.numero, ', ' order by array_position(v_ordenes, o.id)) from fiscal.orden_compra o where o.id = any(v_ordenes))
                        else coalesce(p_datos->>'orden_compra', '') end,
    categoria_gasto = v_categoria, leyenda_cbu_informada = coalesce((p_datos->'leyendas'->>'cbu_informada')::boolean, false),
    leyenda_sujeta_retencion = coalesce((p_datos->'leyendas'->>'sujeta_retencion')::boolean, false),
    jurisdiccion_iibb = case when (v_calc->'importes'->>'percepcion_iibb')::numeric > 0 then coalesce(nullif(v_jur, ''), 'Córdoba') else '' end,
    presupuesto = coalesce(p_datos->>'presupuesto', ''), observaciones = coalesce(p_datos->>'observaciones', ''),
    codigo_autorizacion = coalesce(nullif(btrim(p_datos->>'codigo_autorizacion'), ''), codigo_autorizacion),   -- código de autorización de ARCA
    cae = v_cae, vto_cae = nullif(p_datos->>'vto_cae', '')::date, imagen_path = v_imagen, imagen_nombre = nullif(p_datos->>'imagen_nombre', ''),
    contraparte_tipo_doc = v_prov.tipo_doc, contraparte_doc = v_prov.numero_doc, contraparte_razon = coalesce(v_prov.razon_social, v_prov.nombre),
    contraparte_condicion_iva = v_prov.condicion_iva, contraparte_domicilio = v_prov.domicilio,
    neto_gravado = (v_calc->'importes'->>'neto_gravado')::numeric, no_gravado = (v_calc->'importes'->>'no_gravado')::numeric,
    exento = (v_calc->'importes'->>'exento')::numeric, iva = (v_calc->'importes'->>'iva')::numeric,
    otros_tributos = (v_calc->'importes'->>'otros_tributos')::numeric, percepcion_iva = (v_calc->'importes'->>'percepcion_iva')::numeric,
    percepcion_iibb = (v_calc->'importes'->>'percepcion_iibb')::numeric, total = (v_calc->'importes'->>'total')::numeric
  where id = v_id;
  perform fiscal.guardar_detalle(v_id, '[]', v_calc->'desglose');
  delete from fiscal.compra_orden where comprobante_id = v_id;
  insert into fiscal.compra_orden (comprobante_id, orden_id, posicion) select v_id, x, o::int from unnest(v_ordenes) with ordinality u(x, o);
  select * into v_c from fiscal.comprobante where id = v_id;
  perform fiscal.registrar(p_rol, v_empresa.id, case when v_existente.id is null then 'cargó borrador' else 'modificó borrador' end, 'factura de compra',
    fiscal.etiqueta(v_c), format('%s · %s', v_c.contraparte_razon, fiscal.importe_texto(v_c.total)));
  if p_confirmar then
    update fiscal.comprobante set estado = 'confirmada', confirmado_en = now() where id = v_id returning * into v_c;
    v_ctl := fiscal.aplicar_control_ordenes(v_id);
    if v_ctl is not null and not (v_ctl->>'dentro')::boolean then
      perform fiscal.registrar(p_rol, v_empresa.id, 'quedó en revisión de precio', 'factura de compra', fiscal.etiqueta(v_c),
        format('diferencia %s con sus órdenes de compra; tolerancia %s', fiscal.importe_texto((v_ctl->>'diferencia')::numeric), fiscal.importe_texto((v_ctl->>'tolerancia')::numeric)));
    end if;
    perform fiscal.registrar(p_rol, v_empresa.id, 'confirmó', 'factura de compra', fiscal.etiqueta(v_c),
      format('%s · %s', v_c.contraparte_razon, fiscal.importe_texto(v_c.total)));
  end if;
  return fiscal.idem_guardar(p_clave, 'guardar_compra', p_datos || jsonb_build_object('confirmar', p_confirmar), fiscal.comprobante_json(v_id));
end $$;
