-- =====================================================================
-- Compras con órdenes de compra (US-061, US-062, US-063, US-068).
-- Port de ordenesDisponibles, controlarOrdenes, saldosOrdenes,
-- aprobarRevisionPrecio y bandejaCompras del Simulador Libro de IVA.
-- - La factura se vincula a órdenes recibidas del mismo proveedor y empresa.
-- - Tolerancia: el menor entre 2 % y $ 5.000 (parámetro con fecha de
--   vigencia). Si se pasa, la compra queda en revisión y la aprueba
--   Contador o Gerencia.
-- - Sin orden, la categoría de gasto es obligatoria para confirmar.
-- Las siete órdenes de ejemplo son las de la semilla() del simulador.
-- =====================================================================

-- Espejo mínimo de las Órdenes de Compra del CRM
create table fiscal.orden_compra (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       text not null references fiscal.empresa (id),
  numero           text not null,
  presupuesto      text not null default '',
  proveedor_id     uuid not null references fiscal.contraparte (id),
  estado           text not null check (estado in ('borrador', 'enviada', 'confirmada', 'recibida_parcial', 'recibida', 'cancelada')),
  fecha            date not null,
  fecha_recepcion  date,
  moneda           text not null default 'ARS' check (moneda in ('ARS', 'USD')),
  importe          numeric(14, 2) not null check (importe > 0),
  descripcion      text not null default '',
  creada_por       text not null default '',
  unique (empresa_id, numero)
);

-- Órdenes que cubre cada factura de compra, en el orden en que se eligieron
create table fiscal.compra_orden (
  comprobante_id  uuid not null references fiscal.comprobante (id) on delete cascade,
  orden_id        uuid not null references fiscal.orden_compra (id),
  posicion        int not null,
  primary key (comprobante_id, orden_id)
);

-- Diferencia de precio contra las órdenes que supera la tolerancia
create table fiscal.revision_precio (
  comprobante_id  uuid primary key references fiscal.comprobante (id),
  base            numeric(14, 2) not null,
  saldo           numeric(14, 2) not null,
  diferencia      numeric(14, 2) not null,
  tolerancia      numeric(14, 2) not null,
  aprobada_rol    text,
  aprobada_en     timestamptz
);

-- Categorías de gasto para facturas sin orden de compra (US-062). Lista de ejemplo, administrable.
create table fiscal.categoria_gasto (
  nombre  text primary key,
  orden   int not null
);
insert into fiscal.categoria_gasto (nombre, orden) values
  ('Repuestos e insumos', 1), ('Servicios de terceros', 2), ('Luz, gas y agua', 3), ('Alquiler', 4), ('Fletes', 5), ('Bien de uso', 6), ('Otros gastos', 7);

-- Jurisdicciones de las percepciones de Ingresos Brutos (US-112)
create table fiscal.jurisdiccion (
  nombre  text primary key,
  orden   int not null
);
insert into fiscal.jurisdiccion (nombre, orden) values
  ('Córdoba', 1), ('Buenos Aires', 2), ('Ciudad de Buenos Aires', 3), ('Santa Fe', 4), ('Mendoza', 5), ('Otra', 6);

revoke all on fiscal.orden_compra, fiscal.compra_orden, fiscal.revision_precio, fiscal.categoria_gasto, fiscal.jurisdiccion from public;

-- Categoría de gasto y leyendas del proveedor (US-068) en la factura de compra
alter table fiscal.comprobante
  add column categoria_gasto text not null default '',
  add column leyenda_cbu_informada boolean not null default false,
  add column leyenda_sujeta_retencion boolean not null default false;

insert into fiscal.permiso (accion, rol, texto) values
  ('aprobar_diferencia', 'contador', 'aprobar diferencias de precio contra la orden de compra'),
  ('aprobar_diferencia', 'gerencia', 'aprobar diferencias de precio contra la orden de compra');

-- Las siete órdenes de ejemplo (ficticias), con los proveedores de los datos de ejemplo
insert into fiscal.orden_compra (empresa_id, numero, presupuesto, proveedor_id, estado, fecha, fecha_recepcion, importe, descripcion, creada_por)
select v.empresa_id, v.numero, v.presupuesto, c.id, v.estado, v.fecha::date, nullif(v.recepcion, '')::date, v.importe, v.descripcion, v.creada_por
from (values
  ('MP', 'EJ-0001-OC 1', 'EJ-0001', '33999999943', 'recibida', '2026-09-28', '2026-10-02', 500000.00, 'Componentes del conjunto armado', 'Comprador de ejemplo'),
  ('MP', 'EJ-0002-OC 1', 'EJ-0002', '33999999943', 'recibida', '2026-10-05', '2026-10-07', 120000.00, 'Juego de bielas', 'Comprador de ejemplo'),
  ('MP', 'EJ-0002-OC 2', 'EJ-0002', '30999999952', 'recibida', '2026-10-09', '2026-10-15', 180000.00, 'Fundición de block', 'Compradora de ejemplo'),
  ('MP', 'EJ-0003-OC 1', 'EJ-0003', '33999999943', 'recibida', '2026-10-14', '2026-10-16', 40000.00, 'Kit de juntas', 'Comprador de ejemplo'),
  ('MP', 'EJ-0005-OC 1', 'EJ-0005', '30999999952', 'enviada', '2026-10-20', '', 150000.00, 'Turbo reacondicionado', 'Compradora de ejemplo'),
  ('MP', 'EJ-0001-OC 2', 'EJ-0001', '30999999952', 'recibida', '2026-10-28', '2026-11-04', 200000.00, 'Carcasa fundida', 'Compradora de ejemplo'),
  ('RMP', 'EJ-0007-OC 1', 'EJ-0007', '33999999943', 'recibida', '2026-10-10', '2026-10-14', 900000.00, 'Cigüeñal y tapa de cilindros', 'Comprador de ejemplo')
) v(empresa_id, numero, presupuesto, cuit, estado, fecha, recepcion, importe, descripcion, creada_por)
join fiscal.contraparte c on c.tipo_doc = 80 and c.numero_doc = v.cuit and c.es_proveedor;

-- Las compras de ejemplo ya confirmadas quedan vinculadas como en el simulador (su campo orden_compra ya tenía el número),
-- y la factura C de servicios lleva su categoría. Es la única vez que se toca algo confirmado, y solo en los datos de ejemplo.
insert into fiscal.compra_orden (comprobante_id, orden_id, posicion)
select c.id, o.id, 1
from fiscal.comprobante c join fiscal.orden_compra o on o.empresa_id = c.empresa_id and o.numero = c.orden_compra
where c.operacion = 'compra' and c.orden_compra <> '';
alter table fiscal.comprobante disable trigger t_inmutable;
update fiscal.comprobante set categoria_gasto = 'Servicios de terceros'
where operacion = 'compra' and empresa_id = 'MP' and tipo = 11 and punto_venta = 2 and numero = 50 and contraparte_doc = '27999999986';
alter table fiscal.comprobante enable trigger t_inmutable;

-- Los vínculos con las órdenes solo cambian mientras la compra es borrador
create trigger t_inmutable before insert or update or delete on fiscal.compra_orden
  for each row execute function fiscal.t_detalle_inmutable();

-- ---------------------------------------------------------------------
-- Saldos y control de tolerancia
-- ---------------------------------------------------------------------
-- Importe de la compra sin IVA, en pesos: es lo que se compara con las órdenes de compra
create or replace function fiscal.base_sin_iva(c fiscal.comprobante)
returns numeric language sql immutable as $$
  select round((c.neto_gravado + c.no_gravado + c.exento) * c.cotizacion, 2)
$$;

-- Cuánto de cada orden ya está cubierto por facturas confirmadas. Una factura puede cubrir varias órdenes y una orden
-- puede tener varias facturas: el importe sin IVA de la factura se reparte entre sus órdenes en el orden en que se eligieron.
create or replace function fiscal.saldos_ordenes(p_excluir uuid default null)
returns table (orden_id uuid, facturado numeric, saldo numeric, facturas uuid[]) language plpgsql stable as $$
declare
  c fiscal.comprobante;
  v_fact jsonb := '{}';
  v_lista jsonb := '{}';
  v_resto numeric;
  v_n int;
  v_i int;
  v_prev numeric;
  v_pend numeric;
  v_asig numeric;
  l record;
begin
  for c in select x.* from fiscal.comprobante x join fiscal.tipo_comprobante t on t.codigo = x.tipo
           where x.operacion = 'compra' and x.estado = 'confirmada' and t.clase = 'factura' and x.id is distinct from p_excluir
             and exists (select 1 from fiscal.compra_orden co where co.comprobante_id = x.id)
           order by coalesce(x.confirmado_en, x.creado_en) loop
    v_resto := fiscal.base_sin_iva(c);
    select count(*) into v_n from fiscal.compra_orden co where co.comprobante_id = c.id;
    v_i := 0;
    for l in select co.orden_id as id, o.importe from fiscal.compra_orden co join fiscal.orden_compra o on o.id = co.orden_id
             where co.comprobante_id = c.id order by co.posicion loop
      v_i := v_i + 1;
      v_prev := coalesce((v_fact->>l.id::text)::numeric, 0);
      v_pend := l.importe - v_prev;
      v_asig := v_resto;
      if v_i < v_n then v_asig := case when v_pend <= 0 then 0 when v_resto < v_pend then v_resto else v_pend end; end if;
      v_fact := v_fact || jsonb_build_object(l.id::text, v_prev + v_asig);
      v_lista := v_lista || jsonb_build_object(l.id::text, coalesce(v_lista->(l.id::text), '[]') || to_jsonb(c.id));
      v_resto := v_resto - v_asig;
    end loop;
  end loop;
  return query
    select o.id, coalesce((v_fact->>o.id::text)::numeric, 0), o.importe - coalesce((v_fact->>o.id::text)::numeric, 0),
      coalesce(array(select x::uuid from jsonb_array_elements_text(coalesce(v_lista->(o.id::text), '[]')) x), '{}')
    from fiscal.orden_compra o;
end $$;

-- Compara la factura con el saldo de sus órdenes de compra (US-061). Null si no tiene órdenes o no es factura.
create or replace function fiscal.controlar_ordenes(p_id uuid)
returns jsonb language plpgsql stable as $$
declare
  c fiscal.comprobante;
  v_saldo numeric;
  v_base numeric;
  v_dif numeric;
  v_par jsonb;
  v_tol numeric;
begin
  select * into c from fiscal.comprobante where id = p_id;
  if not exists (select 1 from fiscal.compra_orden where comprobante_id = p_id)
     or (select clase from fiscal.tipo_comprobante where codigo = c.tipo) <> 'factura' then return null; end if;
  select coalesce(sum(s.saldo), 0) into v_saldo from fiscal.saldos_ordenes(p_id) s
  where s.orden_id in (select orden_id from fiscal.compra_orden where comprobante_id = p_id);
  v_base := fiscal.base_sin_iva(c);
  v_dif := v_base - v_saldo;
  v_par := fiscal.parametro_vigente('tolerancia_orden_compra', c.fecha);
  v_tol := least(fiscal.calcular_iva(greatest(v_saldo, 0), (v_par->>'porcentaje')::numeric), (v_par->>'importe')::numeric);
  return jsonb_build_object('base', v_base, 'saldo', v_saldo, 'diferencia', v_dif, 'tolerancia', v_tol, 'dentro', abs(v_dif) <= v_tol);
end $$;

-- Al confirmar: si la diferencia supera la tolerancia, la compra queda en revisión
create or replace function fiscal.aplicar_control_ordenes(p_id uuid)
returns jsonb language plpgsql as $$
declare v jsonb := fiscal.controlar_ordenes(p_id);
begin
  delete from fiscal.revision_precio where comprobante_id = p_id;
  if v is not null and not (v->>'dentro')::boolean then
    insert into fiscal.revision_precio (comprobante_id, base, saldo, diferencia, tolerancia)
    values (p_id, (v->>'base')::numeric, (v->>'saldo')::numeric, (v->>'diferencia')::numeric, (v->>'tolerancia')::numeric);
  end if;
  return v;
end $$;

-- Antes de confirmar: órdenes o categoría (US-061 y US-062)
create or replace function fiscal.exigir_orden_o_categoria(c fiscal.comprobante)
returns void language plpgsql stable as $$
begin
  if (select clase from fiscal.tipo_comprobante where codigo = c.tipo) = 'factura' then
    perform fiscal.req(c.categoria_gasto <> '' or exists (select 1 from fiscal.compra_orden where comprobante_id = c.id), 'VALIDACION',
      'Elegí las órdenes de compra que cubre esta factura o, si no hubo orden, una categoría de gasto.', 'categoria');
  end if;
end $$;

-- Órdenes que se pueden elegir al cargar una factura: recibidas, con saldo, de esa empresa y ese proveedor
-- (más las que ya tiene elegidas el borrador)
create or replace function fiscal.ordenes_disponibles(p_empresa text, p_proveedor uuid, p_compra uuid default null)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'numero', o.numero, 'presupuesto', o.presupuesto, 'estado', o.estado, 'fecha', o.fecha,
      'fecha_recepcion', o.fecha_recepcion, 'importe', o.importe, 'facturado', s.facturado, 'saldo', s.saldo, 'descripcion', o.descripcion,
      'elegida', exists (select 1 from fiscal.compra_orden co where co.comprobante_id = p_compra and co.orden_id = o.id))
    order by o.fecha, o.numero), '[]')
  from fiscal.orden_compra o join fiscal.saldos_ordenes(p_compra) s on s.orden_id = o.id
  where o.empresa_id = p_empresa and o.proveedor_id = p_proveedor and o.estado in ('recibida', 'recibida_parcial')
    and (s.saldo > 0 or exists (select 1 from fiscal.compra_orden co where co.comprobante_id = p_compra and co.orden_id = o.id))
$$;

-- Al importar de ARCA: sugiere la orden de compra (misma empresa y proveedor, saldo parecido al importe sin IVA)
-- o, si no hay, una categoría (27 % → «Luz, gas y agua»; factura C → «Servicios de terceros»)
create or replace function fiscal.sugerir_orden_o_categoria(p_id uuid)
returns void language plpgsql as $$
declare
  c fiscal.comprobante;
  v_par jsonb;
  v_orden uuid;
begin
  select * into c from fiscal.comprobante where id = p_id;
  v_par := fiscal.parametro_vigente('tolerancia_orden_compra', c.fecha);
  select (x->>'id')::uuid into v_orden
  from jsonb_array_elements(fiscal.ordenes_disponibles(c.empresa_id, c.contraparte_id, null)) x
  where abs(fiscal.base_sin_iva(c) - (x->>'saldo')::numeric)
        <= least(fiscal.calcular_iva((x->>'saldo')::numeric, (v_par->>'porcentaje')::numeric), (v_par->>'importe')::numeric)
  order by abs(fiscal.base_sin_iva(c) - (x->>'saldo')::numeric) limit 1;
  if v_orden is not null then
    insert into fiscal.compra_orden (comprobante_id, orden_id, posicion) values (p_id, v_orden, 1);
    update fiscal.comprobante set orden_compra = (select numero from fiscal.orden_compra where id = v_orden) where id = p_id;
  elsif exists (select 1 from fiscal.comprobante_iva where comprobante_id = p_id and alicuota_codigo = 6) then
    update fiscal.comprobante set categoria_gasto = 'Luz, gas y agua' where id = p_id;
  elsif (select letra from fiscal.tipo_comprobante where codigo = c.tipo) = 'C' then
    update fiscal.comprobante set categoria_gasto = 'Servicios de terceros' where id = p_id;
  end if;
end $$;

-- Confirmación de borradores (la usan las importadas de ARCA): ahora exige orden o categoría y controla la tolerancia
create or replace function fiscal.confirmar_compra(p_rol text, p_id uuid)
returns fiscal.comprobante language plpgsql as $$
declare c fiscal.comprobante; v jsonb;
begin
  perform fiscal.exigir(p_rol, 'cargar_compra');
  select * into c from fiscal.comprobante where id = p_id and operacion = 'compra' for update;
  perform fiscal.req(c.id is not null, 'NO_ENCONTRADO', 'El comprobante no existe.');
  perform fiscal.req(c.estado = 'borrador', 'ESTADO_INVALIDO', format('La compra %s ya está %s.', fiscal.etiqueta(c), c.estado));
  perform fiscal.exigir_orden_o_categoria(c);
  perform fiscal.req(c.imagen_path is not null or c.cae <> '' or c.codigo_autorizacion <> '', 'ADJUNTO_OBLIGATORIO',
    'Falta la imagen o el PDF de la factura, su CAE o el código de autorización de ARCA.', 'imagen');
  perform fiscal.exigir_periodo_abierto(c.empresa_id, c.periodo, 'confirmar una compra imputada a ese mes');
  update fiscal.comprobante set estado = 'confirmada', confirmado_en = now() where id = p_id returning * into c;
  v := fiscal.aplicar_control_ordenes(p_id);
  perform fiscal.registrar(p_rol, c.empresa_id, 'confirmó', 'factura de compra', fiscal.etiqueta(c),
    format('%s · %s%s', c.contraparte_razon, fiscal.importe_texto(c.total), case when v is not null and not (v->>'dentro')::boolean then ' · en revisión de precio' else '' end));
  return c;
end $$;

-- ---------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------
create or replace function public.catalogos_compras()
returns jsonb language sql stable security definer set search_path = fiscal, pg_temp as $$
  select jsonb_build_object(
    'categorias', (select jsonb_agg(nombre order by orden) from fiscal.categoria_gasto),
    'jurisdicciones', (select jsonb_agg(nombre order by orden) from fiscal.jurisdiccion),
    'tolerancia', fiscal.parametro_vigente('tolerancia_orden_compra'))
$$;

create or replace function public.ordenes_disponibles(p_empresa text, p_proveedor uuid, p_compra uuid default null)
returns jsonb language sql stable security definer set search_path = fiscal, pg_temp as $$
  select fiscal.ordenes_disponibles(p_empresa, p_proveedor, p_compra)
$$;

-- Aprueba una diferencia de precio contra la orden de compra (US-061)
create or replace function public.aprobar_diferencia(p_rol text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = fiscal, pg_temp as $$
declare r fiscal.revision_precio; c fiscal.comprobante;
begin
  perform fiscal.exigir(p_rol, 'aprobar_diferencia');
  select * into r from fiscal.revision_precio where comprobante_id = p_id for update;
  perform fiscal.req(r.comprobante_id is not null, 'ESTADO_INVALIDO', 'Esa compra no tiene una diferencia de precio para aprobar.');
  perform fiscal.req(r.aprobada_en is null, 'ESTADO_INVALIDO', 'La diferencia ya estaba aprobada.');
  update fiscal.revision_precio set aprobada_rol = p_rol, aprobada_en = now() where comprobante_id = p_id;
  select * into c from fiscal.comprobante where id = p_id;
  perform fiscal.registrar(p_rol, c.empresa_id, 'aprobó diferencia de precio', 'factura de compra', fiscal.etiqueta(c),
    format('diferencia %s', fiscal.importe_texto(r.diferencia)));
  return fiscal.comprobante_json(p_id);
end $$;

-- Órdenes recibidas sin factura (deuda sin documentar), facturas sin orden ni categoría y compras en revisión (US-063)
create or replace function public.bandeja_compras(p_empresa text, p_proveedor uuid default null)
returns jsonb language sql stable security definer set search_path = fiscal, pg_temp as $$
  with s as (select * from fiscal.saldos_ordenes(null)),
  oc as (
    select o.*, s.facturado, s.saldo, p.nombre as proveedor, case when o.fecha_recepcion is null then null else current_date - o.fecha_recepcion end as antiguedad
    from fiscal.orden_compra o join s on s.orden_id = o.id join fiscal.contraparte p on p.id = o.proveedor_id
    where o.empresa_id = p_empresa and (p_proveedor is null or o.proveedor_id = p_proveedor) and o.estado in ('recibida', 'recibida_parcial') and s.saldo > 0
  )
  select jsonb_build_object(
    'ordenes_sin_factura', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'numero', numero, 'presupuesto', presupuesto, 'proveedor', proveedor,
        'proveedor_id', proveedor_id, 'estado', estado, 'fecha', fecha, 'fecha_recepcion', fecha_recepcion, 'importe', importe, 'facturado', facturado,
        'saldo', saldo, 'antiguedad', antiguedad, 'descripcion', descripcion) order by antiguedad desc nulls last) from oc), '[]'),
    'deuda_sin_documentar', coalesce((select sum(saldo) from oc), 0),
    'facturas_sin_orden', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'etiqueta', fiscal.etiqueta(c), 'proveedor', c.contraparte_razon,
        'fecha', c.fecha, 'total', c.total, 'estado', c.estado) order by c.fecha)
      from fiscal.comprobante c join fiscal.tipo_comprobante t on t.codigo = c.tipo
      where c.empresa_id = p_empresa and c.operacion = 'compra' and c.estado <> 'anulada' and t.clase = 'factura' and c.categoria_gasto = ''
        and (p_proveedor is null or c.contraparte_id = p_proveedor)
        and not exists (select 1 from fiscal.compra_orden co where co.comprobante_id = c.id)), '[]'),
    'en_revision', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'etiqueta', fiscal.etiqueta(c), 'proveedor', c.contraparte_razon,
        'base', r.base, 'saldo', r.saldo, 'diferencia', r.diferencia, 'tolerancia', r.tolerancia) order by c.fecha)
      from fiscal.revision_precio r join fiscal.comprobante c on c.id = r.comprobante_id
      where c.empresa_id = p_empresa and c.estado = 'confirmada' and r.aprobada_en is null), '[]'))
$$;

-- Funciones existentes con cambios chicos: guardar_compra (órdenes, categoría, leyendas, jurisdicción y tolerancia),
-- importar_desde_arca (sugiere orden o categoría), comprobante_json y listar_comprobantes (órdenes, categoría y revisión).
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
    condicion_venta = coalesce(p_datos->>'condicion_venta', ''), orden_compra = case when cardinality(v_ordenes) > 0 then (select string_agg(o.numero, ', ' order by array_position(v_ordenes, o.id)) from fiscal.orden_compra o where o.id = any(v_ordenes))
                        else coalesce(p_datos->>'orden_compra', '') end,
    categoria_gasto = v_categoria, leyenda_cbu_informada = coalesce((p_datos->'leyendas'->>'cbu_informada')::boolean, false),
    leyenda_sujeta_retencion = coalesce((p_datos->'leyendas'->>'sujeta_retencion')::boolean, false),
    jurisdiccion_iibb = case when (v_calc->'importes'->>'percepcion_iibb')::numeric > 0 then coalesce(nullif(v_jur, ''), 'Córdoba') else '' end,
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
        perform fiscal.sugerir_orden_o_categoria((v_r->>'id')::uuid);
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
    'revision_precio', (select to_jsonb(r) - 'comprobante_id' from fiscal.revision_precio r where r.comprobante_id = c.id))
  from fiscal.comprobante c join fiscal.tipo_comprobante t on t.codigo = c.tipo
  where c.id = p_id
$$;

create or replace function public.listar_comprobantes(p_empresa text, p_operacion text, p_periodo text default null)
returns jsonb language sql stable security definer set search_path = fiscal, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'operacion', c.operacion, 'tipo', c.tipo, 'tipo_desc', t.descripcion, 'letra', t.letra, 'clase', t.clase,
      'numero_texto', fiscal.numero_comprobante(c.punto_venta, c.numero), 'fecha', c.fecha, 'periodo', c.periodo, 'estado', c.estado,
      'contraparte', c.contraparte_razon, 'documento', case when c.contraparte_tipo_doc = 99 then 'Sin identificar' else fiscal.formatear_cuit(c.contraparte_doc) end,
      'neto_gravado', c.neto_gravado, 'iva', c.iva, 'total', c.total, 'imagen_path', c.imagen_path, 'cae', c.cae,
      'asociado', (select fiscal.etiqueta(a) from fiscal.comprobante a where a.id = c.asociado_id),
      'motivo', c.motivo, 'motivo_anulacion', c.motivo_anulacion, 'orden_compra', c.orden_compra, 'categoria_gasto', c.categoria_gasto, 'origen', c.origen,
      'en_revision', exists (select 1 from fiscal.revision_precio r where r.comprobante_id = c.id and r.aprobada_en is null),
      'periodo_estado', fiscal.estado_periodo(c.empresa_id, c.periodo))
    order by c.fecha desc, c.creado_en desc), '[]'::jsonb)
  from fiscal.comprobante c join fiscal.tipo_comprobante t on t.codigo = c.tipo
  where c.empresa_id = p_empresa and c.operacion = p_operacion and (p_periodo is null or c.periodo = p_periodo)
$$;


do $$
declare f text;
begin
  foreach f in array array['catalogos_compras()', 'ordenes_disponibles(text, uuid, uuid)', 'aprobar_diferencia(text, uuid)', 'bandeja_compras(text, uuid)']
  loop
    execute format('revoke all on function public.%s from public', f);
    if exists (select 1 from pg_roles where rolname = 'anon') then
      execute format('grant execute on function public.%s to anon, authenticated', f);
    end if;
  end loop;
end $$;
