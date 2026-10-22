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
}
export interface Comprobante extends Importes {
  id: string; operacion: Operacion; empresa_id: string; contraparte_id: string; tipo: number; tipo_desc: string; letra: string;
  clase: string; discrimina_iva: boolean; punto_venta: number; numero: number | null; numero_texto: string; etiqueta: string;
  fecha: string; periodo: string; estado: string; modo: 'neto' | 'precio_final'; motivo: string; condicion_venta: string;
  vencimiento_pago: string | null; presupuesto: string; orden_compra: string; remito: string; observaciones: string;
  cae: string; vto_cae: string | null; imagen_path: string | null; imagen_nombre: string | null;
  contraparte_tipo_doc: number | null; contraparte_doc: string | null; contraparte_razon: string; contraparte_condicion_iva: number | null;
  contraparte_domicilio: string; documento: string; condicion_desc: string | null; moneda: string; cotizacion: number;
  creado_rol: string; creado_en: string; emitido_en: string | null; confirmado_en: string | null; anulado_en: string | null;
  motivo_anulacion: string; empresa: Empresa; items: Item[]; desglose: Desglose[];
  asociado: { id: string; etiqueta: string; total: number } | null;
  notas: { id: string; etiqueta: string; total: number; estado: string; fecha: string }[];
  nc_disponible: number | null; asociado_id: string | null;
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
  items: { nivel: 'ok' | 'revisar' | 'bloquea'; texto: string; cantidad: number; ayuda: string }[];
  bloquea: boolean; revisar: number; estado: string;
}
export interface EntradaHistorial { n: number; cuando: string; rol: string; rol_desc: string; empresa_id: string | null; accion: string; entidad: string; ref: string; detalle: string }

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
