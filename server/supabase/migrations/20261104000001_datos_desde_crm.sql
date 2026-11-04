-- Carga los datos de la copia del CRM (esquema crm_copia, solo lectura) en las tablas del módulo (esquema fiscal),
-- para que la página muestre clientes, proveedores, presupuestos de venta y órdenes de compra reales.
-- crm_copia se trae aparte con prototipo/copiar-crm-copia.sql y NUNCA va al repo (datos bajo NDA).
-- Los datos personales vienen cifrados (enc:...): se guardan tal cual, sin intentar leerlos.
-- Se puede correr las veces que haga falta: actualiza por record_id del CRM, no duplica.

alter table fiscal.contraparte  add column if not exists crm_record_id text unique;
alter table fiscal.presupuesto  add column if not exists crm_record_id text unique;
alter table fiscal.presupuesto_linea add column if not exists crm_record_id text unique;
alter table fiscal.orden_compra add column if not exists crm_record_id text unique;

create or replace function fiscal.cargar_desde_crm()
returns jsonb language plpgsql security definer set search_path = fiscal, pg_temp as $$
declare
  v_cli int; v_prov int; v_pres int; v_lin int; v_oc int;
begin
  if to_regclass('crm_copia.clientes') is null then
    perform fiscal.error('SIN_DATOS', 'No está la copia del CRM (esquema crm_copia) en esta base.', null);
  end if;

  -- Clientes. Si el nombre viene cifrado se muestra «Cliente N» (N = número del CRM).
  insert into fiscal.contraparte (crm_record_id, codigo, nombre, es_cliente, razon_social, condicion_iva, domicilio, localidad, provincia, telefono)
  select c.record_id, coalesce(c.id::bigint::text, ''),
         case when coalesce(c.empresa, '') <> '' and c.empresa not like 'enc:%' then c.empresa
              else 'Cliente ' || coalesce(c.id::bigint::text, left(c.record_id, 8)) end,
         true, nullif(c.empresa, ''),
         case c.condicion_fiscal when 'Responsable Inscripto' then 1 when 'Consumidor Final' then 5 when 'Monotributo' then 6
                                 when 'Responsable Monotributo' then 6 when 'Exento' then 4 end,
         coalesce(c.domicilio, ''), coalesce(c.localidad, ''), coalesce(c.provincia, ''), coalesce(c.telefono, '')
  from crm_copia.clientes c
  on conflict (crm_record_id) do update set nombre = excluded.nombre, razon_social = excluded.razon_social, condicion_iva = excluded.condicion_iva,
    domicilio = excluded.domicilio, localidad = excluded.localidad, provincia = excluded.provincia, telefono = excluded.telefono, actualizado_en = now();
  get diagnostics v_cli = row_count;

  -- Proveedores
  insert into fiscal.contraparte (crm_record_id, codigo, nombre, es_proveedor, razon_social, condicion_iva, domicilio, localidad, provincia, telefono, email)
  select p.record_id, coalesce(p.id::bigint::text, ''),
         case when coalesce(p.razon_social, p.empresa, '') <> '' and coalesce(p.razon_social, p.empresa) not like 'enc:%' then coalesce(p.razon_social, p.empresa)
              else 'Proveedor ' || coalesce(p.id::bigint::text, left(p.record_id, 8)) end,
         true, coalesce(nullif(p.razon_social, ''), nullif(p.empresa, '')),
         case p.condicion_fiscal when 'Responsable Inscripto' then 1 when 'Monotributo' then 6 when 'Responsable Monotributo' then 6 when 'Exento' then 4 end,
         coalesce(p.domicilio, ''), coalesce(p.localidad, ''), coalesce(p.provincia, ''), coalesce(p.telefono, ''), coalesce(p.email, '')
  from crm_copia.proveedores p
  on conflict (crm_record_id) do update set nombre = excluded.nombre, razon_social = excluded.razon_social, condicion_iva = excluded.condicion_iva,
    domicilio = excluded.domicilio, localidad = excluded.localidad, provincia = excluded.provincia, telefono = excluded.telefono, email = excluded.email,
    actualizado_en = now();
  get diagnostics v_prov = row_count;

  -- Presupuestos de venta (PV) con cliente y empresa conocidos
  insert into fiscal.presupuesto (crm_record_id, empresa_id, numero, contraparte_id, estado, fecha, moneda, cotizacion, vendedor, descripcion, condiciones)
  select pv.record_id, pv.empresa,
         coalesce(nullif(pv.numero, ''), 'PV-' || pv.numero_pv::bigint::text, 'PV-' || left(pv.record_id, 8)),
         c.id,
         case pv.estado when 'Borrador' then 'armado' when 'En cotización' then 'con_el_cliente' when 'Aprobado' then 'aprobado'
                        when 'En compras' then 'compras' when 'Recibido parcial' then 'recibido' when 'Recibido completo' then 'recibido'
                        when 'Listo para entregar' then 'listo' when 'Entregado' then 'entregado' when 'Cancelado' then 'cancelado'
                        when 'Rechazado' then 'perdido' else 'armado' end,
         coalesce(pv.fecha_envio, pv.created_time::date),
         case when pv.moneda = 'USD' then 'USD' else 'ARS' end, 1,
         coalesce(pv.vendedor_nombre, ''), coalesce(pv.vehiculo, ''), coalesce(pv.condiciones_pago, '')
  from crm_copia.presupuesto_venta pv
  join fiscal.contraparte c on c.crm_record_id = pv.cliente[1]
  where pv.empresa in ('MP', 'RMP')
  on conflict (crm_record_id) do update set estado = excluded.estado, fecha = excluded.fecha, moneda = excluded.moneda,
    vendedor = excluded.vendedor, descripcion = excluded.descripcion, condiciones = excluded.condiciones;
  get diagnostics v_pres = row_count;

  -- Líneas de los PV (solo de presupuestos cargados y con cantidad y precio válidos)
  insert into fiscal.presupuesto_linea (crm_record_id, presupuesto_id, orden, codigo, descripcion, cantidad, precio, descuento, alicuota_codigo)
  select l.record_id, p.id,
         row_number() over (partition by p.id order by l.created_time, l.record_id)
           + coalesce((select max(orden) from fiscal.presupuesto_linea x where x.presupuesto_id = p.id and x.crm_record_id is null), 0),
         coalesce(l.codigo_item, ''), coalesce(nullif(l.descripcion, ''), 'Sin descripción'), l.cantidad,
         coalesce(l.precio_venta_unitario, l.precio_lista, 0), least(greatest(coalesce(l.descuento_linea_pct, 0), 0), 100),
         case coalesce(l.iva_pct, 21) when 0 then 3 when 10.5 then 4 when 27 then 6 else 5 end
  from crm_copia.presupuesto_venta_lineas l
  join fiscal.presupuesto p on p.crm_record_id = l.presupuesto_venta_id[1]
  where l.cantidad > 0 and coalesce(l.precio_venta_unitario, l.precio_lista, 0) >= 0
    and not exists (select 1 from fiscal.presupuesto_linea x where x.crm_record_id = l.record_id);
  get diagnostics v_lin = row_count;

  -- Órdenes de compra (OC) con proveedor conocido e importe mayor que cero
  insert into fiscal.orden_compra (crm_record_id, empresa_id, numero, presupuesto, proveedor_id, estado, fecha, fecha_recepcion, moneda, importe, descripcion, creada_por)
  select oc.record_id, oc.centro_costo,
         coalesce(nullif(oc.numero_display, ''), 'OC-' || oc.numero_oc::bigint::text, 'OC-' || left(oc.record_id, 8)),
         coalesce((select p.numero from fiscal.presupuesto p where p.crm_record_id = coalesce(oc.pv_id, oc.presupuesto_venta[1])), ''),
         c.id,
         case oc.estado when 'Enviada' then 'enviada' when 'Confirmada' then 'confirmada' when 'Recibida parcial' then 'recibida_parcial'
                        when 'Recibida completa' then 'recibida' when 'Cancelada' then 'cancelada' else 'borrador' end,
         coalesce(oc.fecha, oc.created_time::date), oc.fecha_recepcion,
         case when oc.moneda = 'USD' then 'USD' else 'ARS' end, round(oc.total, 2),
         coalesce(oc.observaciones, ''), coalesce(oc.recibido_por_nombre, '')
  from crm_copia.ordenes_compra_mp oc
  join fiscal.contraparte c on c.crm_record_id = oc.proveedor_id
  where oc.centro_costo in ('MP', 'RMP') and coalesce(oc.total, 0) > 0
  on conflict (crm_record_id) do update set estado = excluded.estado, fecha = excluded.fecha, fecha_recepcion = excluded.fecha_recepcion,
    moneda = excluded.moneda, importe = excluded.importe, descripcion = excluded.descripcion;
  get diagnostics v_oc = row_count;

  return jsonb_build_object('clientes', v_cli, 'proveedores', v_prov, 'presupuestos', v_pres, 'lineas_presupuesto', v_lin, 'ordenes_compra', v_oc);
end $$;

revoke all on function fiscal.cargar_desde_crm() from public, anon, authenticated;
