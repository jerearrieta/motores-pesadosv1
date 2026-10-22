/** Formatos es-AR. Solo presentación: los importes ya vienen calculados por el server. */

const fmtImporte = new Intl.NumberFormat('es-AR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export function importe(valor: number | string | null | undefined): string {
  const n = Number(valor ?? 0);
  return fmtImporte.format(Object.is(n, -0) ? 0 : n);
}
export const pesos = (valor: number | string | null | undefined) => `$ ${importe(valor)}`;

export function fecha(iso: string | null | undefined): string {
  if (!iso) return '';
  const [a, m, d] = iso.slice(0, 10).split('-');
  return `${d}/${m}/${a}`;
}
export function fechaHora(iso: string): string {
  return new Date(iso).toLocaleString('es-AR', { dateStyle: 'short', timeStyle: 'short' });
}

const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
export function periodoLargo(p: string): string {
  const [a, m] = p.split('-');
  return `${MESES[Number(m) - 1]} de ${a}`;
}
export const hoy = () => new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 10);

export function cuit(c: string | null | undefined): string {
  return c && /^\d{11}$/.test(c) ? `${c.slice(0, 2)}-${c.slice(2, 10)}-${c.slice(10)}` : (c ?? '');
}

/**
 * Lee lo que escribe una persona ("1.234,56", "1234,5", "800000.50") y lo devuelve como texto
 * con punto decimal ("1234.56"), que es lo que espera el server. null si no es un número.
 */
export function leerNumero(texto: string | null | undefined, decimales = 2): string | null {
  if (texto == null) return null;
  let t = String(texto).trim().replace(/\s/g, '');
  if (!t) return null;
  if (t.includes(',')) t = t.replace(/\./g, '').replace(',', '.');
  else if ((t.match(/\./g) || []).length > 1) t = t.replace(/\./g, '');
  else if (/^\d{1,3}\.\d{3}$/.test(t)) t = t.replace('.', '');   // 1.500 = mil quinientos
  const m = new RegExp(`^(\\d+)(?:\\.(\\d{1,${decimales}}))?$`).exec(t);
  if (!m) return null;
  return m[2] === undefined ? m[1] : `${m[1]}.${m[2]}`;
}

export const ESTADOS: Record<string, { texto: string; color: string }> = {
  borrador: { texto: 'Borrador', color: '' },
  emitido_sin_cae: { texto: 'Emitida sin CAE', color: 'naranja' },
  autorizado: { texto: 'Autorizada', color: 'verde' },
  confirmada: { texto: 'Confirmada', color: 'verde' },
  anulada: { texto: 'Anulada', color: 'rojo' },
};

/* Importe en letras, como en la factura modelo de la empresa */
const U = ['', 'UNO', 'DOS', 'TRES', 'CUATRO', 'CINCO', 'SEIS', 'SIETE', 'OCHO', 'NUEVE', 'DIEZ', 'ONCE', 'DOCE', 'TRECE', 'CATORCE', 'QUINCE', 'DIECISEIS', 'DIECISIETE', 'DIECIOCHO', 'DIECINUEVE',
  'VEINTE', 'VEINTIUNO', 'VEINTIDOS', 'VEINTITRES', 'VEINTICUATRO', 'VEINTICINCO', 'VEINTISEIS', 'VEINTISIETE', 'VEINTIOCHO', 'VEINTINUEVE'];
const D = ['', '', '', 'TREINTA', 'CUARENTA', 'CINCUENTA', 'SESENTA', 'SETENTA', 'OCHENTA', 'NOVENTA'];
const CC = ['', 'CIENTO', 'DOSCIENTOS', 'TRESCIENTOS', 'CUATROCIENTOS', 'QUINIENTOS', 'SEISCIENTOS', 'SETECIENTOS', 'OCHOCIENTOS', 'NOVECIENTOS'];
function menosDeMil(n: number, apocope: boolean): string {
  if (n === 100) return 'CIEN';
  const c = Math.floor(n / 100), r = n % 100;
  let s = c ? CC[c] + (r ? ' ' : '') : '';
  if (r) s += r < 30 ? U[r] : D[Math.floor(r / 10)] + (r % 10 ? ' Y ' + U[r % 10] : '');
  return apocope ? s.replace(/UNO$/, 'UN') : s;
}
function entero(n: bigint, apocope: boolean): string {
  if (n === 0n) return 'CERO';
  const millones = n / 1000000n, resto = n % 1000000n, miles = resto / 1000n, unidades = resto % 1000n, partes: string[] = [];
  if (millones > 0n) partes.push(millones === 1n ? 'UN MILLON' : `${entero(millones, true)} MILLONES`);
  if (miles > 0n) partes.push(miles === 1n ? 'MIL' : `${menosDeMil(Number(miles), true)} MIL`);
  if (unidades > 0n) partes.push(menosDeMil(Number(unidades), apocope));
  return partes.join(' ');
}
export function montoEnLetras(total: number): string {
  const c = BigInt(Math.round(Math.abs(total) * 100));
  const cent = Number(c % 100n);
  return `Son PESOS: ${entero(c / 100n, false)} CON ${cent === 0 ? 'CERO' : menosDeMil(cent, true)} CENTAVO${cent === 1 ? '' : 'S'}`;
}
