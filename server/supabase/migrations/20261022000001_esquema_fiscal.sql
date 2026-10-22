-- =====================================================================
-- Motores Pesados · Prototipo 1.0 · Esquema fiscal
-- Las tablas viven en el esquema "fiscal", que la API de Supabase NO
-- expone. El front solo llega a los datos por las funciones RPC del
-- esquema public (ver 20261022000003_api.sql).
-- Todos los datos son inventados.
-- =====================================================================

create extension if not exists pgcrypto;

create schema if not exists fiscal;
revoke all on schema fiscal from public;

-- ---------------------------------------------------------------------
-- Catálogos (códigos de ARCA)
-- ---------------------------------------------------------------------
create table fiscal.condicion_iva (
  codigo       int primary key,
  descripcion  text not null,
  letra_venta  char(1) check (letra_venta in ('A', 'B'))   -- null = todavía sin letra definida
);

create table fiscal.tipo_comprobante (
  codigo          int primary key,
  descripcion     text not null,
  abreviatura     text not null,
  letra           char(1) not null check (letra in ('A', 'B', 'C')),
  clase           text not null check (clase in ('factura', 'nota_debito', 'nota_credito')),
  discrimina_iva  boolean not null,          -- solo la A da crédito fiscal en compras
  signo           int not null check (signo in (1, -1)),   -- las notas de crédito restan en el libro
  venta           boolean not null,
  compra          boolean not null
);

create table fiscal.alicuota (
  codigo       int primary key,
  descripcion  text not null,
  porcentaje   numeric(5, 2) not null unique,
  soportada    boolean not null default true
);

create table fiscal.tipo_documento (
  codigo       int primary key,
  descripcion  text not null
);

create table fiscal.rol (
  id           text primary key,
  descripcion  text not null
);

-- Quién puede qué. Sin login en esta versión: el rol se elige en la pantalla.
create table fiscal.permiso (
  accion  text not null,
  rol     text not null references fiscal.rol (id),
  texto   text not null,
  primary key (accion, rol)
);

-- ---------------------------------------------------------------------
-- Empresas y puntos de venta
-- ---------------------------------------------------------------------
create table fiscal.empresa (
  id                  text primary key check (id in ('MP', 'RMP')),
  razon_social        text not null,
  nombre_corto        text not null,
  cuit                text not null unique,
  condicion_iva       int not null references fiscal.condicion_iva (codigo),
  domicilio           text not null default '',
  telefono            text not null default '',
  ingresos_brutos     text not null default '',
  inicio_actividades  date,
  leyenda             text not null default ''
);

create table fiscal.punto_venta (
  empresa_id   text not null references fiscal.empresa (id),
  numero       int not null check (numero between 1 and 99999),
  descripcion  text not null default '',
  primary key (empresa_id, numero)
);

-- Numerador propio por empresa + punto de venta + tipo. Se toma con
-- SELECT ... FOR UPDATE: sin secuencias, para que no queden huecos.
create table fiscal.numerador (
  empresa_id   text not null,
  punto_venta  int not null,
  tipo         int not null references fiscal.tipo_comprobante (codigo),
  ultimo       int not null default 0,
  primary key (empresa_id, punto_venta, tipo),
  foreign key (empresa_id, punto_venta) references fiscal.punto_venta (empresa_id, numero)
);

-- ---------------------------------------------------------------------
-- Clientes y proveedores (una sola tabla)
-- ---------------------------------------------------------------------
create table fiscal.contraparte (
  id               uuid primary key default gen_random_uuid(),
  codigo           text not null default '',
  nombre           text not null,
  es_cliente       boolean not null default false,
  es_proveedor     boolean not null default false,
  tipo_doc         int references fiscal.tipo_documento (codigo),
  numero_doc       text,
  razon_social     text,
  condicion_iva    int references fiscal.condicion_iva (codigo),
  domicilio        text not null default '',
  localidad        text not null default '',
  provincia        text not null default '',
  telefono         text not null default '',
  email            text not null default '',
  ingresos_brutos  text not null default '',
  creado_en        timestamptz not null default now(),
  actualizado_en   timestamptz not null default now(),
  check (es_cliente or es_proveedor)
);

-- ---------------------------------------------------------------------
-- Comprobantes: ventas y compras en la misma tabla (tipo de operación)
-- ---------------------------------------------------------------------
create table fiscal.comprobante (
  id              uuid primary key default gen_random_uuid(),
  operacion       text not null check (operacion in ('venta', 'compra')),
  empresa_id      text not null references fiscal.empresa (id),
  contraparte_id  uuid not null references fiscal.contraparte (id),
  tipo            int not null references fiscal.tipo_comprobante (codigo),
  punto_venta     int not null check (punto_venta between 1 and 99999),
  numero          int check (numero between 1 and 99999999),   -- en ventas lo pone la base al emitir
  fecha           date not null,
  periodo         text not null check (periodo ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  estado          text not null check (estado in ('borrador', 'emitido_sin_cae', 'autorizado', 'confirmada', 'anulada')),
  modo            text not null default 'neto' check (modo in ('neto', 'precio_final')),
  asociado_id     uuid references fiscal.comprobante (id),     -- la factura que corrige una NC o ND
  motivo          text not null default '',
  condicion_venta text not null default '',
  vencimiento_pago date,
  presupuesto     text not null default '',
  orden_compra    text not null default '',
  remito          text not null default '',
  observaciones   text not null default '',
  cae             text not null default '' check (cae = '' or cae ~ '^\d{14}$'),
  vto_cae         date,
  imagen_path     text,
  imagen_nombre   text,
  -- Foto de los datos de la contraparte al momento de emitir o cargar
  contraparte_tipo_doc       int,
  contraparte_doc            text,
  contraparte_razon          text,
  contraparte_condicion_iva  int,
  contraparte_domicilio      text not null default '',
  -- Importes con centavos, nunca float
  moneda          text not null default 'ARS' check (moneda in ('ARS', 'USD')),
  cotizacion      numeric(14, 6) not null default 1 check (cotizacion > 0),
  neto_gravado    numeric(14, 2) not null default 0,
  no_gravado      numeric(14, 2) not null default 0,
  exento          numeric(14, 2) not null default 0,
  iva             numeric(14, 2) not null default 0,
  otros_tributos  numeric(14, 2) not null default 0,
  percepcion_iva  numeric(14, 2) not null default 0,
  percepcion_iibb numeric(14, 2) not null default 0,
  total           numeric(14, 2) not null default 0,
  -- Auditoría
  creado_rol      text not null,
  creado_en       timestamptz not null default now(),
  emitido_en      timestamptz,
  confirmado_en   timestamptz,
  anulado_en      timestamptz,
  anulado_rol     text,
  motivo_anulacion text not null default '',
  -- La cuenta que siempre tiene que cerrar
  constraint total_cierra check (total = neto_gravado + no_gravado + exento + iva + otros_tributos + percepcion_iva + percepcion_iibb),
  constraint estado_segun_operacion check (
    (operacion = 'venta' and estado in ('borrador', 'emitido_sin_cae', 'autorizado'))
    or (operacion = 'compra' and estado in ('borrador', 'confirmada', 'anulada'))),
  constraint anulacion_con_motivo check (estado <> 'anulada' or motivo_anulacion <> '')
);

-- Una venta no repite número; una compra no se carga dos veces (salvo anulada)
create unique index uq_venta_numero on fiscal.comprobante (empresa_id, tipo, punto_venta, numero)
  where operacion = 'venta' and numero is not null;
create unique index uq_compra_numero on fiscal.comprobante (empresa_id, contraparte_doc, tipo, punto_venta, numero)
  where operacion = 'compra' and estado <> 'anulada';
create index ix_comprobante_libro on fiscal.comprobante (empresa_id, operacion, periodo);

create table fiscal.comprobante_linea (
  id               uuid primary key default gen_random_uuid(),
  comprobante_id   uuid not null references fiscal.comprobante (id) on delete cascade,
  orden            int not null,
  codigo           text not null default '',
  descripcion      text not null,
  cantidad         numeric(14, 4) not null check (cantidad > 0),
  precio_lista     numeric(16, 4) not null check (precio_lista >= 0),
  descuento        numeric(5, 2) not null default 0 check (descuento between 0 and 100),
  precio_unitario  numeric(16, 4) not null,
  alicuota_codigo  int not null references fiscal.alicuota (codigo),
  importe_neto     numeric(14, 2) not null,
  unique (comprobante_id, orden)
);

-- IVA separado por alícuota: se calcula sobre la SUMA de netos, no línea por línea
create table fiscal.comprobante_iva (
  comprobante_id   uuid not null references fiscal.comprobante (id) on delete cascade,
  alicuota_codigo  int not null references fiscal.alicuota (codigo),
  base             numeric(14, 2) not null,
  iva              numeric(14, 2) not null,
  primary key (comprobante_id, alicuota_codigo)
);

-- ---------------------------------------------------------------------
-- Períodos de IVA e historial
-- ---------------------------------------------------------------------
create table fiscal.periodo_iva (
  empresa_id  text not null references fiscal.empresa (id),
  periodo     text not null check (periodo ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  estado      text not null default 'abierto' check (estado in ('abierto', 'cerrado')),
  cerrado_rol text,
  cerrado_en  timestamptz,
  primary key (empresa_id, periodo)
);

-- Solo altas: nunca se edita ni se borra
create table fiscal.historial (
  n           bigserial primary key,
  cuando      timestamptz not null default now(),
  rol         text not null,
  empresa_id  text,
  accion      text not null,
  entidad     text not null,
  ref         text not null default '',
  detalle     text not null default ''
);

-- Reintentos seguros: la misma clave devuelve la misma respuesta
create table fiscal.idempotencia (
  clave         uuid primary key,
  funcion       text not null,
  request_hash  text not null,
  respuesta     jsonb not null,
  creada        timestamptz not null default now()
);

-- Nadie de afuera toca las tablas directamente
revoke all on all tables in schema fiscal from public;
revoke all on all sequences in schema fiscal from public;
