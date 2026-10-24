/**
 * Rutas del módulo dentro de «Bandeja Tesorería». Cada pantalla tiene su dirección:
 * se puede compartir el enlace y al recargar se vuelve al mismo lugar.
 * Las rutas anteriores (/libro, /ventas, /compras, /cierre) redirigen acá (ver next.config.ts).
 */
export const BANDEJA = '/bandeja-tesoreria';

/** Pestañas que la bandeja ya tiene en el CRM: acá se ven apagadas, solo marcan el lugar. */
export const PESTANAS_CRM = ['Cobros por validar', 'Cartera', 'Cheques', 'Órdenes de Pago', 'Cuentas a pagar', 'Pago Cta. Cte.',
  'Facturas Prov.', 'Caja Chica', 'Extracto', 'Alertas'];

export interface Pestana {
  id: string; texto: string; icono: string;
  /** Qué borradores cuenta la marca de la pestaña */
  contador?: 'venta' | 'compra';
  sub?: { id: string; texto: string }[];
}

export const PESTANAS: Pestana[] = [
  { id: 'facturas-de-compra', texto: 'Facturas de compra', icono: 'carro', contador: 'compra' },
  { id: 'facturas-de-venta', texto: 'Facturas de venta', icono: 'recibo', contador: 'venta', sub: [
    { id: 'facturas-emitidas', texto: 'Facturas emitidas' },
    { id: 'emitir-desde-un-presupuesto-de-venta', texto: 'Emitir desde un presupuesto de venta' },
  ] },
  { id: 'libro-de-iva', texto: 'Libro de IVA', icono: 'libro', sub: [
    { id: 'libro-y-posicion', texto: 'Libro y posición' },
    { id: 'conciliacion-con-arca', texto: 'Conciliación con ARCA' },
    { id: 'cierre-e-historial', texto: 'Cierre e historial' },
  ] },
];

export const RUTAS = {
  libro: `${BANDEJA}/libro-de-iva/libro-y-posicion`,
  conciliacion: `${BANDEJA}/libro-de-iva/conciliacion-con-arca`,
  cierre: `${BANDEJA}/libro-de-iva/cierre-e-historial`,
  ventas: `${BANDEJA}/facturas-de-venta/facturas-emitidas`,
  emitirPresupuesto: `${BANDEJA}/facturas-de-venta/emitir-desde-un-presupuesto-de-venta`,
  compras: `${BANDEJA}/facturas-de-compra`,
  cargarCompra: `${BANDEJA}/facturas-de-compra/cargar-factura-de-compra`,
  importarArca: `${BANDEJA}/facturas-de-compra/importar-desde-arca`,
  ordenesSinFactura: `${BANDEJA}/facturas-de-compra/ordenes-de-compra-sin-factura`,
};

/** Pestaña y subpestaña activas según la dirección. */
export function ubicar(ruta: string) {
  const [, , p, s] = ruta.split('/');
  const pestana = PESTANAS.find((x) => x.id === p) ?? null;
  const subpestana = pestana?.sub?.find((x) => x.id === s) ?? null;
  return { pestana, subpestana };
}
