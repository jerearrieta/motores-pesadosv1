-- =====================================================================
-- Emitir desde un presupuesto de venta tildando líneas, con facturación
-- parcial: cada línea del presupuesto se factura una sola vez (R-12),
-- también si está en un borrador. Un presupuesto en dólares se factura
-- en pesos por defecto, con «EQUIVALE A DOLARES U$D …» en cada línea
-- (precioEnPesos y aDosDecimales del Simulador Libro de IVA).
-- Los presupuestos EJ-0001 a EJ-0007 son los ficticios de la semilla().
-- También: consumidor final identificado desde el monto del parámetro
-- vigente (RG 5866), en lugar del monto fijo.
-- =====================================================================

create table fiscal.presupuesto (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      text not null references fiscal.empresa (id),
  numero          text not null,
  contraparte_id  uuid not null references fiscal.contraparte (id),
  estado          text not null check (estado in ('armado', 'con_el_cliente', 'aprobado', 'compras', 'recibido', 'listo', 'entregado', 'cancelado', 'perdido')),
  fecha           date not null,
  moneda          text not null default 'ARS' check (moneda in ('ARS', 'USD')),
  cotizacion      numeric(14, 6) not null default 1 check (cotizacion > 0),
  vendedor        text not null default '',
  descripcion     text not null default '',
  condiciones     text not null default '',
  unique (empresa_id, numero)
);

create table fiscal.presupuesto_linea (
  id               uuid primary key default gen_random_uuid(),
  presupuesto_id   uuid not null references fiscal.presupuesto (id) on delete cascade,
  orden            int not null,
  codigo           text not null default '',
  descripcion      text not null,
  cantidad         numeric(14, 4) not null check (cantidad > 0),
  precio           numeric(16, 4) not null check (precio >= 0),
  descuento        numeric(5, 2) not null default 0 check (descuento between 0 and 100),
  alicuota_codigo  int not null references fiscal.alicuota (codigo),
  unique (presupuesto_id, orden)
);
revoke all on fiscal.presupuesto, fiscal.presupuesto_linea from public;

alter table fiscal.comprobante
  add column presupuesto_id uuid references fiscal.presupuesto (id),
  add column origen_moneda text not null default '' check (origen_moneda in ('', 'USD')),
  add column origen_cotizacion numeric(14, 6);
alter table fiscal.comprobante_linea add column presupuesto_linea_id uuid references fiscal.presupuesto_linea (id);
-- R-12: una línea del presupuesto está en un solo comprobante (también cuenta el borrador)
create unique index uq_linea_presupuesto on fiscal.comprobante_linea (presupuesto_linea_id) where presupuesto_linea_id is not null;

-- Presupuestos de ejemplo (ficticios), con los clientes de los datos de ejemplo
insert into fiscal.presupuesto (empresa_id, numero, contraparte_id, estado, fecha, moneda, cotizacion, vendedor, descripcion, condiciones) values
  ('MP', 'EJ-0001', '00000000-0000-0000-0000-0000000000c1', 'aprobado', '2026-10-05', 'ARS', 1, 'Vendedora de ejemplo', 'Conjunto armado (ficticio)', '50% anticipo y 50% saldo'),
  ('MP', 'EJ-0002', '00000000-0000-0000-0000-0000000000c2', 'compras', '2026-10-14', 'ARS', 1, 'Vendedor de ejemplo', 'Rectificación de block y bielas (ficticio)', 'Cuenta corriente 30'),
  ('MP', 'EJ-0003', '00000000-0000-0000-0000-0000000000c3', 'listo', '2026-10-16', 'ARS', 1, 'Vendedora de ejemplo', 'Kit de juntas (ficticio)', 'Contado'),
  ('MP', 'EJ-0004', '00000000-0000-0000-0000-0000000000c4', 'aprobado', '2026-10-19', 'ARS', 1, 'Vendedor de ejemplo', 'Reparación de culata (ficticio)', '50% anticipo y 50% saldo'),
  ('MP', 'EJ-0005', '00000000-0000-0000-0000-0000000000c1', 'armado', '2026-10-20', 'ARS', 1, 'Vendedora de ejemplo', 'Turbo reacondicionado (ficticio)', 'A convenir'),
  ('MP', 'EJ-0006', '00000000-0000-0000-0000-0000000000c2', 'cancelado', '2026-10-02', 'ARS', 1, 'Vendedor de ejemplo', 'Bomba de aceite (ficticio)', 'Contado'),
  ('RMP', 'EJ-0007', '00000000-0000-0000-0000-0000000000c1', 'entregado', '2026-10-17', 'USD', 1050, 'Vendedora de ejemplo', 'Rectificación de cigüeñal (ficticio)', 'Contado');
insert into fiscal.presupuesto_linea (presupuesto_id, orden, codigo, descripcion, cantidad, precio, descuento, alicuota_codigo)
select p.id, v.orden, v.codigo, v.descripcion, v.cantidad, v.precio, v.descuento, v.alicuota
from (values
  ('EJ-0001', 1, 'CONJ-001', 'Conjunto armado', 1, 800000.0000, 0, 5),
  ('EJ-0002', 1, 'BIE-2200', 'Juego de bielas (repuestos)', 2, 95000.0000, 0, 5),
  ('EJ-0002', 2, 'MO-RECT', 'Rectificación de block (mano de obra)', 1, 60000.0000, 0, 4),
  ('EJ-0003', 1, 'JUN-QSB', 'Kit de juntas', 4, 12500.0000, 5, 5),
  ('EJ-0004', 1, 'CUL-REP', 'Reparación de culata', 1, 45000.0000, 0, 5),
  ('EJ-0005', 1, 'TUR-REA', 'Turbo reacondicionado', 1, 230000.0000, 0, 5),
  ('EJ-0006', 1, 'BOM-ACE', 'Bomba de aceite', 1, 38000.0000, 0, 5),
  ('EJ-0007', 1, 'CIG-RECT', 'Rectificación de cigüeñal', 1, 1200.0000, 0, 5),
  ('EJ-0007', 2, 'TAP-RECT', 'Rectificación de tapa de cilindros', 1, 800.0000, 0, 5)
) v(numero, orden, codigo, descripcion, cantidad, precio, descuento, alicuota)
join fiscal.presupuesto p on p.numero = v.numero;

-- La factura de ejemplo del presupuesto EJ-0001 y el borrador del EJ-0005 quedan enlazados a sus líneas
-- (solo en los datos de ejemplo; por eso se apagan un momento los disparadores de inmutabilidad).
alter table fiscal.comprobante disable trigger t_inmutable;
alter table fiscal.comprobante_linea disable trigger t_inmutable;
update fiscal.comprobante c set presupuesto_id = p.id
from fiscal.presupuesto p where c.operacion = 'venta' and c.empresa_id = p.empresa_id and c.presupuesto = p.numero;
update fiscal.comprobante_linea l set presupuesto_linea_id = pl.id
from fiscal.comprobante c, fiscal.presupuesto_linea pl
where l.comprobante_id = c.id and pl.presupuesto_id = c.presupuesto_id and pl.codigo = l.codigo and l.codigo <> '';
alter table fiscal.comprobante enable trigger t_inmutable;
alter table fiscal.comprobante_linea enable trigger t_inmutable;

-- ---------------------------------------------------------------------
-- Dólares a pesos
-- ---------------------------------------------------------------------
-- Precio unitario en dólares a pesos: round(precio × cotización, 4)
create or replace function fiscal.precio_en_pesos(p_precio numeric, p_cotizacion numeric)
returns numeric language sql immutable as $$
  select round(p_precio * p_cotizacion, 4)
$$;

-- «12556215.0000» a «12556215.00» (para mostrar un precio unitario con dos decimales)
create or replace function fiscal.a_dos_decimales(p_valor numeric)
returns numeric language sql immutable as $$
  select round(p_valor, 2)
$$;

-- Número con punto de miles y coma decimal, sin ceros de más: 1050 → «1.050», 1050.5 → «1.050,5»
create or replace function fiscal.numero_corto(p numeric)
returns text language sql immutable as $$
  select replace(to_char(trunc(abs(p)), 'FM999G999G999G990'), ',', '.')
    || coalesce(',' || nullif(rtrim(split_part(abs(p)::text, '.', 2), '0'), ''), '')
$$;

create or replace function fiscal.estado_presupuesto_texto(p text)
returns text language sql immutable as $$
  select case p when 'armado' then 'Armado' when 'con_el_cliente' then 'Con el cliente' when 'aprobado' then 'Aprobado' when 'compras' then 'Compras'
    when 'recibido' then 'Recibido' when 'listo' then 'Listo' when 'entregado' then 'Entregado' when 'cancelado' then 'Cancelado' when 'perdido' then 'Perdido' else p end
$$;

-- Se factura desde «Aprobado» en adelante, si no está cancelado ni perdido (R-10)
create or replace function fiscal.presupuesto_facturable(p_estado text)
returns boolean language sql immutable as $$
  select p_estado in ('aprobado', 'compras', 'recibido', 'listo', 'entregado')
$$;

-- Líneas listas para calcular a partir de las líneas tildadas del presupuesto. Si está en dólares y se emite en pesos,
-- cada precio se convierte con la cotización y la descripción dice la equivalencia en dólares, como en el modelo de factura.
create or replace function fiscal.lineas_presupuesto(p_presupuesto uuid, p_ids jsonb, p_emitir_en text, p_cotizacion text)
returns jsonb language plpgsql stable as $$
declare
  v_pres fiscal.presupuesto;
  v_ids uuid[];
  v_cot numeric;
  v_pesos boolean;
  v_lineas jsonb;
begin
  select * into v_pres from fiscal.presupuesto where id = p_presupuesto;
  perform fiscal.req(v_pres.id is not null, 'NO_ENCONTRADO', 'El presupuesto de venta no existe.');
  begin
    v_ids := array(select x::uuid from jsonb_array_elements_text(coalesce(p_ids, '[]')) x);
  exception when others then
    perform fiscal.error('VALIDACION', 'Alguna de las líneas elegidas no existe.', 'lineas');
  end;
  perform fiscal.req(cardinality(v_ids) > 0, 'VALIDACION', 'Tildá la casilla de cada línea del presupuesto de venta que querés facturar.', 'lineas');
  perform fiscal.req(cardinality(v_ids) = (select count(*) from fiscal.presupuesto_linea where presupuesto_id = v_pres.id and id = any(v_ids)), 'VALIDACION',
    'Alguna de las líneas elegidas no es de este presupuesto de venta.', 'lineas');
  v_pesos := v_pres.moneda = 'USD' and coalesce(nullif(p_emitir_en, ''), 'pesos') = 'pesos';
  if v_pres.moneda = 'USD' then
    v_cot := fiscal.leer_decimal(to_jsonb(coalesce(nullif(btrim(p_cotizacion), ''), v_pres.cotizacion::text)), 6, 'cotizacion');
    perform fiscal.req(v_cot > 0, 'VALIDACION', 'La cotización tiene que ser mayor que cero.', 'cotizacion');
  end if;
  select jsonb_agg(jsonb_build_object(
      'presupuesto_linea_id', l.id, 'codigo', l.codigo, 'alicuota_codigo', l.alicuota_codigo, 'cantidad', l.cantidad::text, 'descuento', l.descuento::text,
      'precio', case when v_pesos then fiscal.precio_en_pesos(l.precio, v_cot) else l.precio end::text,
      'descripcion', case when v_pesos
        then l.descripcion || E'\n' || format('EQUIVALE A DOLARES U$D %s + IVA ($ %s)',
               fiscal.numero_corto(round(l.cantidad * round(l.precio * (100 - l.descuento) / 100, 4), 2)), fiscal.numero_corto(v_cot))
        else l.descripcion end)
    order by l.orden)
  into v_lineas
  from fiscal.presupuesto_linea l where l.presupuesto_id = v_pres.id and l.id = any(v_ids);
  return v_lineas;
end $$;

-- ---------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------
create or replace function public.presupuestos(p_empresa text)
returns jsonb language sql stable security definer set search_path = fiscal, pg_temp as $$
  select coalesce(jsonb_agg(x order by x->>'numero'), '[]') from (
    select jsonb_build_object(
      'id', p.id, 'numero', p.numero, 'estado', p.estado, 'estado_texto', fiscal.estado_presupuesto_texto(p.estado),
      'facturable', fiscal.presupuesto_facturable(p.estado), 'fecha', p.fecha, 'moneda', p.moneda, 'cotizacion', p.cotizacion,
      'vendedor', p.vendedor, 'descripcion', p.descripcion, 'condiciones', p.condiciones,
      'cliente', jsonb_build_object('id', c.id, 'nombre', c.nombre, 'faltantes', to_jsonb(fiscal.faltantes(c)), 'completo', cardinality(fiscal.faltantes(c)) = 0),
      'importes', fiscal.calcular_venta((select jsonb_agg(jsonb_build_object('descripcion', l.descripcion, 'cantidad', l.cantidad::text, 'precio', l.precio::text,
          'descuento', l.descuento::text, 'alicuota_codigo', l.alicuota_codigo) order by l.orden) from fiscal.presupuesto_linea l where l.presupuesto_id = p.id), 'neto')->'importes',
      'lineas', (select jsonb_agg(jsonb_build_object('id', l.id, 'orden', l.orden, 'codigo', l.codigo, 'descripcion', l.descripcion, 'cantidad', l.cantidad,
          'precio', l.precio, 'descuento', l.descuento, 'alicuota_codigo', l.alicuota_codigo,
          'neto', round(l.cantidad * round(l.precio * (100 - l.descuento) / 100, 4), 2),
          'facturada', (select jsonb_build_object('id', v.id, 'etiqueta', case when v.estado = 'borrador' then 'un borrador' else fiscal.etiqueta(v) end, 'estado', v.estado)
                        from fiscal.comprobante_linea cl join fiscal.comprobante v on v.id = cl.comprobante_id where cl.presupuesto_linea_id = l.id limit 1))
          order by l.orden) from fiscal.presupuesto_linea l where l.presupuesto_id = p.id)) as x
    from fiscal.presupuesto p join fiscal.contraparte c on c.id = p.contraparte_id
    where p.empresa_id = p_empresa) q
$$;

-- Líneas convertidas para la vista previa (el mismo armado que usa guardar_venta)
create or replace function public.preparar_lineas_presupuesto(p_presupuesto uuid, p_lineas jsonb, p_emitir_en text, p_cotizacion text)
returns jsonb language sql stable security definer set search_path = fiscal, pg_temp as $$
  select fiscal.lineas_presupuesto(p_presupuesto, p_lineas, p_emitir_en, p_cotizacion)
$$;

-- Funciones existentes con cambios chicos: calcular_venta y guardar_detalle (llevan la línea del presupuesto)
-- y guardar_venta (presupuesto, líneas tildadas, dólares y consumidor final con el parámetro vigente).
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
      'alicuota_codigo', (l->>'alicuota_codigo')::int, 'importe_neto', v_neto, 'presupuesto_linea_id', l->'presupuesto_linea_id');
    v_bases := v_bases || jsonb_build_object('alicuota_codigo', (l->>'alicuota_codigo')::int, 'base', v_neto);
  end loop;
  v_desglose := fiscal.desglosar(v_bases);
  if p_modo = 'precio_final' then
    -- el IVA es la diferencia: el total impreso tiene que ser exactamente el que se cobró
    v_desglose := jsonb_build_array(jsonb_set(v_desglose->0, '{iva}', to_jsonb((v_total - v_neto)::numeric(14, 2))));
  end if;
  return jsonb_build_object('items', v_items, 'desglose', v_desglose, 'importes', fiscal.importes_desde_desglose(v_desglose));
end $$;

create or replace function fiscal.guardar_detalle(p_id uuid, p_items jsonb, p_desglose jsonb)
returns void language plpgsql as $$
begin
  delete from fiscal.comprobante_linea where comprobante_id = p_id;
  delete from fiscal.comprobante_iva where comprobante_id = p_id;
  insert into fiscal.comprobante_linea (comprobante_id, orden, codigo, descripcion, cantidad, precio_lista, descuento, precio_unitario, alicuota_codigo, importe_neto, presupuesto_linea_id)
  select p_id, (i->>'orden')::int, i->>'codigo', i->>'descripcion', (i->>'cantidad')::numeric, (i->>'precio_lista')::numeric, (i->>'descuento')::numeric,
         (i->>'precio_unitario')::numeric, (i->>'alicuota_codigo')::int, (i->>'importe_neto')::numeric,
         nullif(i->>'presupuesto_linea_id', '')::uuid
  from jsonb_array_elements(coalesce(p_items, '[]')) i;
  insert into fiscal.comprobante_iva (comprobante_id, alicuota_codigo, base, iva)
  select p_id, (d->>'alicuota_codigo')::int, (d->>'base')::numeric, (d->>'iva')::numeric
  from jsonb_array_elements(coalesce(p_desglose, '[]')) d;
end $$;

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
  v_pres fiscal.presupuesto;
  v_lineas jsonb := p_datos->'lineas';
  v_moneda text := 'ARS';
  v_cot numeric := 1;
  v_origen text := '';
  v_lin record;
  v_otro fiscal.comprobante;
  v_par jsonb;
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

  -- Desde un presupuesto de venta: las líneas salen del presupuesto (las tildadas), no de lo que manda el front
  if nullif(p_datos->>'presupuesto_id', '') is not null then
    select * into v_pres from fiscal.presupuesto where id = (p_datos->>'presupuesto_id')::uuid;
    perform fiscal.req(v_pres.id is not null, 'NO_ENCONTRADO', 'El presupuesto de venta no existe.');
    perform fiscal.req(v_pres.empresa_id = v_empresa.id, 'EMPRESA_DISTINTA', 'El presupuesto de venta es de la otra empresa.');
    perform fiscal.req(fiscal.presupuesto_facturable(v_pres.estado), 'ESTADO_INVALIDO',
      format('El presupuesto de venta %s está «%s». Se factura desde «Aprobado» en adelante, si no está cancelado ni perdido.', v_pres.numero, fiscal.estado_presupuesto_texto(v_pres.estado)));
    perform fiscal.req(v_pres.contraparte_id = v_cli.id, 'VALIDACION', 'El cliente no coincide con el del presupuesto de venta.', 'contraparte_id');
    perform fiscal.req(v_modo = 'neto', 'VALIDACION', 'Desde un presupuesto de venta se factura con el precio de lista sin IVA.', 'modo');
    v_lineas := fiscal.lineas_presupuesto(v_pres.id, p_datos->'presupuesto_lineas', p_datos->>'emitir_en', p_datos->>'cotizacion');
    if v_pres.moneda = 'USD' then
      v_cot := fiscal.leer_decimal(to_jsonb(coalesce(nullif(btrim(p_datos->>'cotizacion'), ''), v_pres.cotizacion::text)), 6, 'cotizacion');
      if coalesce(nullif(p_datos->>'emitir_en', ''), 'pesos') = 'dolares' then v_moneda := 'USD'; else v_origen := 'USD'; end if;
    end if;
    -- Cada línea del presupuesto se factura una sola vez, también si está en un borrador (R-12)
    for v_lin in select (x->>'presupuesto_linea_id')::uuid as pl from jsonb_array_elements(v_lineas) x loop
      v_otro := null;
      select c.* into v_otro from fiscal.comprobante_linea l join fiscal.comprobante c on c.id = l.comprobante_id
      where l.presupuesto_linea_id = v_lin.pl and c.id is distinct from v_id limit 1;
      perform fiscal.req(v_otro.id is null, 'LINEA_YA_FACTURADA', format('La línea «%s» ya está en %s.',
        (select descripcion from fiscal.presupuesto_linea where id = v_lin.pl), case when v_otro.estado = 'borrador' then 'un borrador' else fiscal.etiqueta(v_otro) end), 'lineas');
    end loop;
  end if;

  v_calc := fiscal.calcular_venta(v_lineas, v_modo);
  select letra_venta into v_letra from fiscal.condicion_iva where codigo = v_cli.condicion_iva;

  if p_emitir then
    perform fiscal.req(cardinality(fiscal.faltantes(v_cli)) = 0, 'DATOS_FISCALES_INCOMPLETOS',
      format('El cliente «%s» no tiene datos fiscales completos (%s). Completalos en Clientes.', v_cli.nombre, array_to_string(fiscal.faltantes(v_cli), ', ')), 'contraparte_id');
    perform fiscal.req(v_letra is not null, 'TIPO_INVALIDO',
      format('La condición «%s» todavía no tiene una letra de factura definida. Consultalo con el contador.', (select descripcion from fiscal.condicion_iva where codigo = v_cli.condicion_iva)), 'contraparte_id');
    perform fiscal.exigir_periodo_abierto(v_empresa.id, to_char(v_fecha, 'YYYY-MM'), 'emitir con fecha de ese mes');
    -- RG 5866: desde $ 10.000.000 hay que identificar al consumidor final
    -- el monto sale del parámetro vigente a la fecha de la factura, en pesos
    v_par := fiscal.parametro_vigente('identificar_consumidor_final', v_fecha);
    perform fiscal.req(v_par is null or not (v_letra = 'B' and v_cli.tipo_doc = 99
        and round((v_calc->'importes'->>'total')::numeric * case when v_moneda = 'USD' then v_cot else 1 end, 2) >= (v_par->>'desde')::numeric), 'DATOS_FISCALES_INCOMPLETOS',
      format('Desde %s hay que identificar al consumidor final con CUIT, CUIL o DNI (%s). Completá sus datos fiscales.', fiscal.importe_texto((v_par->>'desde')::numeric), v_par->>'fuente'), 'contraparte_id');
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
    remito = coalesce(p_datos->>'remito', ''), presupuesto = case when v_pres.id is not null then v_pres.numero else coalesce(p_datos->>'presupuesto', '') end, presupuesto_id = v_pres.id,
    moneda = v_moneda, cotizacion = case when v_moneda = 'USD' then v_cot else 1 end, origen_moneda = v_origen,
    origen_cotizacion = case when v_origen <> '' then v_cot end, observaciones = coalesce(p_datos->>'observaciones', ''),
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


do $$
declare f text;
begin
  foreach f in array array['presupuestos(text)', 'preparar_lineas_presupuesto(uuid, jsonb, text, text)']
  loop
    execute format('revoke all on function public.%s from public', f);
    if exists (select 1 from pg_roles where rolname = 'anon') then
      execute format('grant execute on function public.%s to anon, authenticated', f);
    end if;
  end loop;
end $$;
