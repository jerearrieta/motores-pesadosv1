/**
 * Llamadas al server (funciones RPC de Supabase, ver server/supabase/migrations/…_api.sql).
 * El client no calcula importes para guardar ni arma números de comprobante: los pide acá.
 */
import { supabase, BUCKET_COMPROBANTES } from './supabase';

export type Rol = 'administracion' | 'contador' | 'gerencia' | 'admin_tecnico' | 'lectura';
export type Operacion = 'venta' | 'compra';

export interface Empresa {
  id: string; razon_social: string; nombre_corto: string; cuit: string; condicion_iva: number;
  domicilio: string; telefono: string; ingresos_brutos: string; inicio_actividades: string | null; leyenda: string;
}
export interface TipoComprobante {
  codigo: number; descripcion: string; abreviatura: string; letra: 'A' | 'B' | 'C';
  clase: 'factura' | 'nota_debito' | 'nota_credito'; discrimina_iva: boolean; signo: number; venta: boolean; compra: boolean;
}
export interface Catalogos {
  empresas: Empresa[];
  puntos_venta: { empresa_id: string; numero: number; descripcion: string }[];
  tipos: TipoComprobante[];
  condiciones: { codigo: number; descripcion: string; letra_venta: string | null }[];
  alicuotas: { codigo: number; descripcion: string; porcentaje: number }[];
  tipos_documento: { codigo: number; descripcion: string }[];
  roles: { id: Rol; descripcion: string }[];
  permisos: Record<string, Rol[]>;
}
export interface Contraparte {
  id: string; codigo: string; nombre: string; es_cliente: boolean; es_proveedor: boolean;
  tipo_doc: number | null; numero_doc: string | null; razon_social: string | null; condicion_iva: number | null;
  domicilio: string; localidad: string; provincia: string; telefono: string; email: string; ingresos_brutos: string;
  documento: string; condicion_desc: string | null; faltantes: string[]; completo: boolean;
  /** Empresas con las que operó (ventas si es cliente, compras si es proveedor) */
  empresas: string[];
}
export interface Importes {
  neto_gravado: number; no_gravado: number; exento: number; iva: number; otros_tributos: number;
  percepcion_iva: number; percepcion_iibb: number; total: number;
}
export interface Desglose { alicuota_codigo: number; porcentaje: number; base: number; iva: number }
export interface Item {
  orden: number; codigo: string; descripcion: string; cantidad: number; precio_lista: number; descuento: number;
  precio_unitario: number; alicuota_codigo: number; importe_neto: number;
}
export interface ComprobanteResumen {
  id: string; operacion: Operacion; tipo: number; tipo_desc: string; letra: string; clase: string; numero_texto: string;
  fecha: string; periodo: string; estado: string; contraparte: string; documento: string;
  neto_gravado: number; iva: number; total: number; imagen_path: string | null; cae: string;
  asociado: string | null; motivo: string; motivo_anulacion: string; periodo_estado: string;
  orden_compra?: string; categoria_gasto?: string; origen?: 'manual' | 'arca'; en_revision?: boolean;
}
export interface Comprobante extends Importes {
  id: string; operacion: Operacion; empresa_id: string; contraparte_id: string; tipo: number; tipo_desc: string; letra: string;
  clase: string; discrimina_iva: boolean; punto_venta: number; numero: number | null; numero_texto: string; etiqueta: string;
  fecha: string; periodo: string; estado: string; modo: 'neto' | 'precio_final'; motivo: string; condicion_venta: string;
  vencimiento_pago: string | null; presupuesto: string; orden_compra: string; remito: string; observaciones: string;
  cae: string; vto_cae: string | null; imagen_path: string | null; imagen_nombre: string | null;
  contraparte_tipo_doc: number | null; contraparte_doc: string | null; contraparte_razon: string; contraparte_condicion_iva: number | null;
  contraparte_domicilio: string; documento: string; origen: 'manual' | 'arca'; codigo_autorizacion: string; origen_moneda: '' | 'USD'; origen_cotizacion: number | null; condicion_desc: string | null; moneda: string; cotizacion: number;
  creado_rol: string; creado_en: string; emitido_en: string | null; confirmado_en: string | null; anulado_en: string | null;
  motivo_anulacion: string; empresa: Empresa; items: Item[]; desglose: Desglose[];
  asociado: { id: string; etiqueta: string; total: number } | null;
  notas: { id: string; etiqueta: string; total: number; estado: string; fecha: string }[];
  nc_disponible: number | null; asociado_id: string | null;
  categoria_gasto: string; leyenda_cbu_informada: boolean; leyenda_sujeta_retencion: boolean; jurisdiccion_iibb: string;
  ordenes: { id: string; numero: string; presupuesto: string; importe: number }[];
  revision_precio: RevisionPrecio | null;
  /** Solo en la factura B: líneas con el IVA incluido (el centavo de redondeo va a la última) */
  lineas_iva_incluido: { orden: number; lista: number; unitario: number; total: number }[] | null;
}
/** Diferencia de precio contra las órdenes de compra que supera la tolerancia */
export interface RevisionPrecio { base: number; saldo: number; diferencia: number; tolerancia: number; aprobada_rol: string | null; aprobada_en: string | null }
export interface OrdenDisponible {
  id: string; numero: string; presupuesto: string; estado: string; fecha: string; fecha_recepcion: string | null; importe: number;
  facturado: number; saldo: number; descripcion: string; elegida: boolean;
}
export interface CatalogosCompras { categorias: string[]; jurisdicciones: string[]; tolerancia: { porcentaje: number; importe: number; fuente: string; vigente_desde: string } }
export interface BandejaCompras {
  ordenes_sin_factura: (Omit<OrdenDisponible, 'elegida'> & { proveedor: string; proveedor_id: string; antiguedad: number | null })[];
  deuda_sin_documentar: number;
  facturas_sin_orden: { id: string; etiqueta: string; proveedor: string; fecha: string; total: number; estado: string }[];
  en_revision: { id: string; etiqueta: string; proveedor: string; base: number; saldo: number; diferencia: number; tolerancia: number }[];
}
export interface Calculo { items?: Item[]; desglose: Desglose[]; importes: Importes }
export interface FilaLibro {
  id: string; fecha: string; tipo: number; tipo_desc: string; letra: string; numero: string; contraparte: string; documento: string;
  condicion: string; estado: string; n21: number; i21: number; n105: number; i105: number; n27: number; i27: number;
  n_otras: number; i_otras: number; n0: number; no_gravado: number; exento: number; otros_tributos: number;
  perc_iva: number; perc_iibb: number; iva: number; total: number; neto: number; no_gravado_exento: number; moneda: string; cotizacion: number; cae: string; imagen_path: string | null;
}
export type TotalesLibro = Omit<FilaLibro, 'id' | 'fecha' | 'tipo' | 'tipo_desc' | 'letra' | 'numero' | 'contraparte' | 'documento' | 'condicion' | 'estado' | 'moneda' | 'cotizacion' | 'cae' | 'imagen_path'> & { cantidad: number };
export interface Libro { filas: FilaLibro[]; totales: TotalesLibro }
export interface Posicion {
  empresa_id: string; periodo: string; estado: 'abierto' | 'cerrado'; debito: number; credito: number; saldo: number;
  perc_iva: number; perc_iibb: number; ventas: number; compras: number;
}
export interface Pendientes {
  items: { nivel: 'ok' | 'revisar' | 'bloquea' | 'info'; texto: string; cantidad: number; ayuda: string }[];
  bloquea: boolean; revisar: number; estado: string;
}
export interface EntradaHistorial { n: number; cuando: string; rol: string; rol_desc: string; empresa_id: string | null; accion: string; entidad: string; ref: string; detalle: string }

export type TipoArchivoArca = 'recibidos' | 'emitidos';
export type EstadoConciliacion = 'coincide' | 'difiere' | 'falta_sistema' | 'falta_arca' | 'anulada_sistema' | 'en_borrador';
/** Un comprobante leído del archivo de «Mis Comprobantes» de ARCA */
export interface ComprobanteArca {
  fila: number; fecha: string; tipo: number; punto_venta: number; numero: number; cae: string; tipo_doc: number; cuit: string; nombre: string;
  moneda: 'PES' | 'DOL'; cotizacion: number; neto_gravado: number; no_gravado: number; exento: number; otros_tributos: number; iva: number; total: number;
  desglose: { alicuota_codigo: number; base: number; iva: number }[] | null; observaciones: string[];
}
export interface FilaConciliacion {
  estado: EstadoConciliacion; etiqueta: string; contraparte: string; cuit: string | null; detalle: string[]; importable?: boolean;
  arca?: ComprobanteArca; sistema?: { id: string; etiqueta: string; estado: string; fecha: string; total: number; iva: number };
}
export interface TotalesConciliacion { neto: number; iva: number; total: number }
export interface Conciliacion {
  filas: FilaConciliacion[]; fuera: number; resumen: Record<EstadoConciliacion, number>; tot_arca: TotalesConciliacion; tot_sistema: TotalesConciliacion;
}
export interface ResultadoConciliacion {
  lectura: { errores: string[]; columnas: string[]; detalle_alicuotas: boolean; fila_titulos: number | null; cantidad: number };
  comprobantes: ComprobanteArca[]; conciliacion: Conciliacion | null;
}

/** Presupuesto de venta del CRM (espejo mínimo), con lo ya facturado de cada línea */
export interface Presupuesto {
  id: string; numero: string; estado: string; estado_texto: string; facturable: boolean; fecha: string; moneda: 'ARS' | 'USD'; cotizacion: number;
  vendedor: string; descripcion: string; condiciones: string;
  cliente: { id: string; nombre: string; faltantes: string[]; completo: boolean };
  importes: Importes;
  lineas: { id: string; orden: number; codigo: string; descripcion: string; cantidad: number; precio: number; descuento: number; alicuota_codigo: number; neto: number;
    facturada: { id: string; etiqueta: string; estado: string } | null }[];
}

/** Error de negocio que devuelve el server: el código decide qué hace el front, el detalle es para la persona. */
export class ErrorNegocio extends Error {
  constructor(public codigo: string, public detalle: string, public campo: string | null) {
    super(detalle || codigo);
  }
}

async function rpc<T>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  if (!supabase) throw new ErrorNegocio('SIN_CONFIGURAR', 'Falta configurar Supabase (ver client/.env.example).', null);
  const { data, error } = await supabase.rpc(fn, args);
  if (error) {
    const codigo = /^[A-Z_]+$/.test(error.message) ? error.message : 'ERROR';
    throw new ErrorNegocio(codigo, codigo === 'ERROR' ? error.message : error.details ?? error.message, error.hint || null);
  }
  return data as T;
}

const clave = () => crypto.randomUUID();

export const api = {
  catalogos: () => rpc<Catalogos>('catalogos'),
  contrapartes: (tipo?: 'cliente' | 'proveedor') => rpc<Contraparte[]>('listar_contrapartes', { p_tipo: tipo ?? null }),
  guardarContraparte: (rol: Rol, datos: Record<string, unknown>) => rpc<Contraparte>('guardar_contraparte', { p_rol: rol, p_datos: datos }),
  comprobantes: (empresa: string, operacion: Operacion, periodo?: string) =>
    rpc<ComprobanteResumen[]>('listar_comprobantes', { p_empresa: empresa, p_operacion: operacion, p_periodo: periodo ?? null }),
  comprobante: (id: string) => rpc<Comprobante>('obtener_comprobante', { p_id: id }),
  calcular: (datos: Record<string, unknown>) => rpc<Calculo>('calcular_comprobante', { p_datos: datos }),
  guardarVenta: (rol: Rol, datos: Record<string, unknown>, emitir: boolean) =>
    rpc<Comprobante>('guardar_venta', { p_rol: rol, p_datos: datos, p_emitir: emitir, p_clave: emitir ? clave() : null }),
  emitirNota: (rol: Rol, datos: Record<string, unknown>) => rpc<Comprobante>('emitir_nota_venta', { p_rol: rol, p_datos: datos, p_clave: clave() }),
  guardarCompra: (rol: Rol, datos: Record<string, unknown>, confirmar: boolean) =>
    rpc<Comprobante>('guardar_compra', { p_rol: rol, p_datos: datos, p_confirmar: confirmar, p_clave: confirmar ? clave() : null }),
  anularCompra: (rol: Rol, id: string, motivo: string) => rpc<Comprobante>('anular_compra', { p_rol: rol, p_id: id, p_motivo: motivo }),
  eliminarBorrador: (rol: Rol, id: string) => rpc<void>('eliminar_borrador', { p_rol: rol, p_id: id }),
  libro: (empresa: string, periodo: string, operacion: Operacion) => rpc<Libro>('libro_iva', { p_empresa: empresa, p_periodo: periodo, p_operacion: operacion }),
  posicion: (empresa: string, periodo: string) => rpc<Posicion>('posicion_iva', { p_empresa: empresa, p_periodo: periodo }),
  periodos: (empresa: string) => rpc<Posicion[]>('periodos_iva', { p_empresa: empresa }),
  pendientesCierre: (empresa: string, periodo: string) => rpc<Pendientes>('pendientes_cierre', { p_empresa: empresa, p_periodo: periodo }),
  cerrarPeriodo: (rol: Rol, empresa: string, periodo: string) => rpc<Posicion>('cerrar_periodo', { p_rol: rol, p_empresa: empresa, p_periodo: periodo }),
  historial: (rol: Rol, empresa?: string) => rpc<EntradaHistorial[]>('ver_historial', { p_rol: rol, p_empresa: empresa ?? null }),
  conciliarArca: (rol: Rol, empresa: string, periodo: string, tipo: TipoArchivoArca, archivo: string, texto: string) =>
    rpc<ResultadoConciliacion>('conciliar_arca', { p_rol: rol, p_empresa: empresa, p_periodo: periodo, p_tipo_archivo: tipo, p_archivo: archivo, p_texto: texto }),
  importarDesdeArca: (rol: Rol, empresa: string, tipo: TipoArchivoArca, comprobantes: ComprobanteArca[]) =>
    rpc<{ creados: { id: string; etiqueta: string; estado: string; total: number }[]; errores: string[] }>('importar_desde_arca',
      { p_rol: rol, p_empresa: empresa, p_tipo_archivo: tipo, p_comprobantes: comprobantes }),
  confirmarImportadas: (rol: Rol, empresa: string) =>
    rpc<{ ok: { id: string; etiqueta: string }[]; pendientes: { id: string; etiqueta: string; motivo: string }[] }>('confirmar_importadas', { p_rol: rol, p_empresa: empresa }),
  archivoEjemploArca: (empresa: string, periodo: string, tipo: TipoArchivoArca) =>
    rpc<string>('archivo_ejemplo_arca', { p_empresa: empresa, p_periodo: periodo, p_tipo_archivo: tipo }),
  resumenIvaSimple: (empresa: string, periodo: string) =>
    rpc<import('./exportar').ResumenIvaSimple>('resumen_iva_simple', { p_empresa: empresa, p_periodo: periodo }),
  catalogosCompras: () => rpc<CatalogosCompras>('catalogos_compras'),
  ordenesDisponibles: (empresa: string, proveedor: string, compra?: string | null) =>
    rpc<OrdenDisponible[]>('ordenes_disponibles', { p_empresa: empresa, p_proveedor: proveedor, p_compra: compra ?? null }),
  aprobarDiferencia: (rol: Rol, id: string) => rpc<Comprobante>('aprobar_diferencia', { p_rol: rol, p_id: id }),
  bandejaCompras: (empresa: string) => rpc<BandejaCompras>('bandeja_compras', { p_empresa: empresa, p_proveedor: null }),
  presupuestos: (empresa: string) => rpc<Presupuesto[]>('presupuestos', { p_empresa: empresa }),
  prepararLineasPresupuesto: (presupuesto: string, lineas: string[], emitirEn: 'pesos' | 'dolares', cotizacion: string) =>
    rpc<Record<string, unknown>[]>('preparar_lineas_presupuesto', { p_presupuesto: presupuesto, p_lineas: lineas, p_emitir_en: emitirEn, p_cotizacion: cotizacion }),
  clientesPorPrioridad: (empresa?: string | null) =>
    rpc<{ id: string; nombre: string; completo: boolean; presupuestos: number; monto: number; empresas: string[]; activo: boolean }[]>('clientes_por_prioridad', { p_empresa: empresa ?? null }),
  exportarFacturas: (empresa: string, periodo?: string) => rpc<Record<string, unknown>[]>('exportar_facturas', { p_empresa: empresa, p_periodo: periodo ?? null }),
};

/** Sube la imagen o el PDF de una factura de compra y devuelve la ruta dentro del bucket. */
export async function subirImagen(empresa: string, archivo: File): Promise<string> {
  if (!supabase) throw new ErrorNegocio('SIN_CONFIGURAR', 'Falta configurar Supabase.', null);
  const ext = (archivo.name.split('.').pop() || 'bin').toLowerCase().replace(/[^a-z0-9]/g, '');
  const ruta = `${empresa}/${new Date().toISOString().slice(0, 7)}/${crypto.randomUUID()}.${ext}`;
  const { error } = await supabase.storage.from(BUCKET_COMPROBANTES).upload(ruta, archivo, { contentType: archivo.type, upsert: false });
  if (error) throw new ErrorNegocio('ADJUNTO', `No se pudo subir el archivo: ${error.message}`, 'imagen');
  return ruta;
}

/** URL temporal (10 minutos) para ver una imagen guardada. */
export async function urlImagen(ruta: string): Promise<string | null> {
  if (!supabase) return null;
  const { data } = await supabase.storage.from(BUCKET_COMPROBANTES).createSignedUrl(ruta, 600);
  return data?.signedUrl ?? null;
}
