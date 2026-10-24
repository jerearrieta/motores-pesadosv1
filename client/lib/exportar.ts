/**
 * Exportación a Excel con las columnas de prototipo-libro-iva.xlsx:
 * hoja «Facturas» (lo que guarda la base), los dos libros y la posición.
 * Los importes vienen del server; acá solo se escriben.
 */
import { api, type Empresa, type FilaLibro, type Posicion } from './api';
import { periodoLargo } from './formato';

const FMT_IMPORTE = '#,##0.00;[Red]-#,##0.00';

const COLUMNAS_FACTURAS: [string, string, 'm' | 'f' | 't'][] = [
  ['operacion', 'Operación', 't'], ['empresa', 'Empresa', 't'], ['tipo_comprobante', 'Tipo de comprobante', 't'], ['letra', 'Letra', 't'],
  ['punto_venta', 'Pto. venta', 't'], ['numero', 'Número', 't'], ['fecha', 'Fecha', 'f'], ['periodo', 'Período', 't'],
  ['contraparte', 'Contraparte (cliente o proveedor)', 't'], ['cuit', 'CUIT', 't'], ['condicion_iva', 'Condición IVA contraparte', 't'],
  ['condicion_venta', 'Condición de venta', 't'], ['neto_21', 'Neto gravado 21%', 'm'], ['neto_10_5', 'Neto gravado 10,5%', 'm'],
  ['neto_27', 'Neto gravado 27%', 'm'], ['no_gravado', 'No gravado / Exento', 'm'], ['iva_21', 'IVA 21%', 'm'], ['iva_10_5', 'IVA 10,5%', 'm'],
  ['iva_27', 'IVA 27%', 'm'], ['percepcion_iva', 'Percepción de IVA', 'm'], ['percepcion_iibb', 'Percepción de Ingresos Brutos', 'm'], ['total', 'TOTAL', 'm'],
  ['cae', 'CAE', 't'], ['vto_cae', 'Vto. CAE', 'f'], ['imagen', 'Imagen de la factura', 't'], ['presupuesto', 'Presupuesto de Venta', 't'],
  ['orden_compra', 'Orden de Compra', 't'], ['comprobante_asociado', 'Comprobante que corrige (NC/ND)', 't'], ['estado', 'Estado', 't'],
  ['motivo_anulacion', 'Motivo de anulación', 't'],
];

const aFecha = (iso: unknown) => (typeof iso === 'string' && iso ? new Date(`${iso.slice(0, 10)}T12:00:00`) : null);

export async function exportarExcel(empresa: Empresa, periodo: string) {
  const [{ default: ExcelJS }, facturas, ventas, compras, posicion] = await Promise.all([
    import('exceljs'),
    api.exportarFacturas(empresa.id, periodo),
    api.libro(empresa.id, periodo, 'venta'),
    api.libro(empresa.id, periodo, 'compra'),
    api.posicion(empresa.id, periodo),
  ]);
  const wb = new ExcelJS.Workbook();
  wb.creator = 'Motores Pesados · Prototipo 1.0';
  wb.created = new Date();

  const encabezado = (ws: import('exceljs').Worksheet) => {
    const f = ws.getRow(1);
    f.font = { bold: true, color: { argb: 'FFFFFFFF' } };
    f.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF0E1730' } };
    f.alignment = { vertical: 'middle', wrapText: true };
    f.height = 30;
    ws.views = [{ state: 'frozen', ySplit: 1 }];
  };

  // Hoja Facturas: una fila por comprobante, como la hoja del Excel prototipo
  const wf = wb.addWorksheet('Facturas');
  wf.columns = [{ header: 'ID', key: 'id', width: 6 }, ...COLUMNAS_FACTURAS.map(([k, t, tipo]) => ({
    header: t, key: k, width: tipo === 'm' ? 15 : k === 'contraparte' ? 32 : 14,
    style: tipo === 'm' ? { numFmt: FMT_IMPORTE } : tipo === 'f' ? { numFmt: 'dd/mm/yyyy' } : {},
  }))];
  facturas.forEach((f, i) => wf.addRow({ id: i + 1, ...f, fecha: aFecha(f.fecha), vto_cae: aFecha(f.vto_cae) }));
  encabezado(wf);

  // Libros separados de ventas y compras
  const libro = (nombre: string, operacion: 'Venta' | 'Compra', filas: FilaLibro[]) => {
    const ws = wb.addWorksheet(nombre);
    const ultima = operacion === 'Venta' ? 'DÉBITO FISCAL (ventas)' : 'CRÉDITO FISCAL (compras)';
    const m = { numFmt: FMT_IMPORTE };
    ws.columns = [
      { header: 'Empresa', key: 'empresa', width: 9 }, { header: 'Período', key: 'periodo', width: 10 },
      { header: 'Fecha', key: 'fecha', width: 12, style: { numFmt: 'dd/mm/yyyy' } }, { header: 'Operación', key: 'operacion', width: 10 },
      { header: 'Comprobante', key: 'comprobante', width: 32 }, { header: 'Contraparte', key: 'contraparte', width: 32 },
      { header: 'CUIT', key: 'cuit', width: 16 }, { header: 'Condición IVA', key: 'condicion', width: 24 },
      { header: 'Neto gravado', key: 'neto', width: 15, style: m }, { header: 'No gravado / Exento', key: 'no_gravado', width: 15, style: m },
      { header: 'IVA 21%', key: 'i21', width: 14, style: m }, { header: 'IVA 10,5%', key: 'i105', width: 14, style: m },
      { header: 'IVA 27%', key: 'i27', width: 14, style: m }, { header: 'IVA otras alícuotas', key: 'i_otras', width: 14, style: m },
      { header: 'Percepción de IVA', key: 'perc_iva', width: 14, style: m }, { header: 'Percepción de Ingresos Brutos', key: 'perc_iibb', width: 14, style: m },
      { header: 'TOTAL', key: 'total', width: 16, style: m }, { header: ultima, key: 'fiscal', width: 18, style: m },
    ];
    for (const f of filas) {
      ws.addRow({
        empresa: empresa.id, periodo, fecha: aFecha(f.fecha), operacion, comprobante: `${f.tipo_desc} ${f.numero}`, contraparte: f.contraparte,
        cuit: f.documento, condicion: f.condicion, neto: f.neto, no_gravado: f.no_gravado_exento,
        i21: f.i21, i105: f.i105, i27: f.i27, i_otras: f.i_otras, perc_iva: f.perc_iva, perc_iibb: f.perc_iibb, total: f.total, fiscal: f.iva,
      });
    }
    const n = filas.length;
    const t = ws.addRow({ comprobante: `Totales (${n} comprobantes)` });
    for (const col of ['neto', 'no_gravado', 'i21', 'i105', 'i27', 'i_otras', 'perc_iva', 'perc_iibb', 'total', 'fiscal']) {
      const letra = ws.getColumn(col).letter;
      t.getCell(col).value = n ? { formula: `SUM(${letra}2:${letra}${n + 1})` } : 0;
    }
    t.font = { bold: true };
    encabezado(ws);
  };
  libro('Libro IVA Ventas', 'Venta', ventas.filas);
  libro('Libro IVA Compras', 'Compra', compras.filas);

  // Posición: débito − crédito (las percepciones se informan aparte)
  const wp = wb.addWorksheet('Posición IVA');
  const p: Posicion = posicion;
  wp.columns = [{ header: 'Concepto', key: 'c', width: 44 }, { header: 'Importe', key: 'v', width: 18, style: { numFmt: FMT_IMPORTE } }];
  wp.addRows([
    { c: `${empresa.razon_social} · período ${periodo} (${p.estado})` },
    { c: 'Débito fiscal (IVA ventas)', v: p.debito },
    { c: 'Crédito fiscal (IVA compras)', v: p.credito },
    { c: p.saldo >= 0 ? 'SALDO DE IVA A PAGAR' : 'SALDO DE IVA A FAVOR', v: p.saldo },
    {},
    { c: 'Percepciones de IVA sufridas (informativo)', v: p.perc_iva },
    { c: 'Percepciones de Ingresos Brutos sufridas (informativo)', v: p.perc_iibb },
  ]);
  wp.getRow(5).font = { bold: true };
  encabezado(wp);

  const buffer = await wb.xlsx.writeBuffer();
  const url = URL.createObjectURL(new Blob([buffer], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = `libro-iva-${empresa.id}-${periodo}.xlsx`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
}

export interface ResumenIvaSimple {
  periodo: string;
  debito: { alicuota: string; neto: number; iva: number }[];
  credito: { alicuota: string; neto: number; iva: number }[];
  posicion: Posicion;
  ajustes: { tipo: string; comprobante: string; contraparte: string; detalle: string; importe: number }[];
  conciliaciones: { tipo: 'emitidos' | 'recibidos'; cuando: string | null; archivo: string | null;
    resumen: Record<string, number> | null; diferencias: { estado: string; etiqueta: string; contraparte: string; cuit: string | null; detalle: string[];
      sistema?: { total: number } }[] }[];
}

const ESTADO_CONCILIACION: Record<string, string> = {
  coincide: 'Coincide', difiere: 'Difiere', falta_sistema: 'Falta en el sistema', falta_arca: 'Falta en ARCA',
  anulada_sistema: 'Anulada en el sistema', en_borrador: 'En borrador',
};

/**
 * Excel para IVA Simple (RG 5705): hojas Resumen, Ajustes y, si se concilió ese período, Diferencias ARCA.
 * El período es el de la pantalla desde donde se exporta. Es un borrador para el contador: el nombre empieza con BORRADOR_.
 */
export async function exportarIvaSimple(empresa: Empresa, periodo: string) {
  const [{ default: ExcelJS }, r] = await Promise.all([import('exceljs'), api.resumenIvaSimple(empresa.id, periodo)]);
  const wb = new ExcelJS.Workbook();
  wb.creator = 'Motores Pesados · Prototipo 1.0';
  wb.created = new Date();
  const titulo = (ws: import('exceljs').Worksheet, texto: string) => {
    ws.addRow([`${texto} - ${empresa.razon_social}`]).font = { bold: true, size: 13 };
    ws.addRow([`CUIT ${empresa.cuit.replace(/^(\d{2})(\d{8})(\d)$/, '$1-$2-$3')} - Período ${periodo} (${periodoLargo(periodo)})`]);
    ws.addRow([`Generado el ${new Date().toLocaleString('es-AR')}`]);
    ws.addRow(['Incluye comprobantes de prueba, sin validez fiscal']);
    ws.addRow([]);
  };
  const cabecera = (ws: import('exceljs').Worksheet, valores: string[]) => {
    const f = ws.addRow(valores);
    f.font = { bold: true, color: { argb: 'FFFFFFFF' } };
    f.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF0E1730' } };
  };

  const wr = wb.addWorksheet('Resumen');
  wr.columns = [{ width: 30 }, { width: 22 }, { width: 18 }, { width: 18 }, { width: 22 }, { width: 18 }];
  titulo(wr, 'Resumen para IVA Simple');
  cabecera(wr, ['Libro', 'Alícuota', 'Neto gravado', 'IVA']);
  for (const x of r.debito) wr.addRow(['Ventas (débito fiscal)', x.alicuota, Number(x.neto), Number(x.iva)]);
  for (const x of r.credito) wr.addRow(['Compras (crédito fiscal)', x.alicuota, Number(x.neto), Number(x.iva)]);
  wr.addRow([]);
  const p = r.posicion;
  wr.addRow(['Débito fiscal', '', '', Number(p.debito)]);
  wr.addRow(['Crédito fiscal', '', '', Number(p.credito)]);
  wr.addRow([Number(p.saldo) >= 0 ? 'Saldo a pagar' : 'Saldo a favor', '', '', Math.abs(Number(p.saldo))]).font = { bold: true };
  wr.addRow([]);
  cabecera(wr, ['Conciliación con ARCA', 'Estado', 'Coinciden', 'Diferencias', 'Faltan en el sistema', 'Faltan en ARCA']);
  for (const c of r.conciliaciones) {
    wr.addRow([c.tipo === 'emitidos' ? 'Ventas (emitidos)' : 'Compras (recibidos)', c.cuando ? `Hecha el ${new Date(c.cuando).toLocaleDateString('es-AR')}` : 'No hecha',
      ...(c.resumen ? [c.resumen.coincide, c.resumen.difiere, c.resumen.falta_sistema, c.resumen.falta_arca] : ['', '', '', ''])]);
  }
  wr.getColumn(3).numFmt = FMT_IMPORTE; wr.getColumn(4).numFmt = FMT_IMPORTE;

  const wa = wb.addWorksheet('Ajustes');
  wa.columns = [{ width: 70 }, { width: 30 }, { width: 30 }, { width: 40 }, { width: 16 }];
  titulo(wa, 'Ajustes a revisar en IVA Simple');
  cabecera(wa, ['Ajuste', 'Comprobante', 'Contraparte', 'Detalle', 'Importe']);
  for (const a of r.ajustes) wa.addRow([a.tipo, a.comprobante, a.contraparte, a.detalle, Number(a.importe)]);
  if (!r.ajustes.length) wa.addRow(['No hay ajustes para este período.']);
  wa.getColumn(5).numFmt = FMT_IMPORTE;

  const hechas = r.conciliaciones.filter((c) => c.cuando);
  if (hechas.length) {
    const wd = wb.addWorksheet('Diferencias ARCA');
    wd.columns = [{ width: 20 }, { width: 20 }, { width: 32 }, { width: 30 }, { width: 16 }, { width: 16 }, { width: 90 }];
    titulo(wd, 'Diferencias con Mis Comprobantes');
    cabecera(wd, ['Archivo', 'Estado', 'Comprobante', 'Contraparte', 'CUIT', 'Total sistema', 'Detalle']);
    for (const c of hechas) {
      for (const d of c.diferencias) {
        wd.addRow([c.tipo === 'emitidos' ? 'Ventas (emitidos)' : 'Compras (recibidos)', ESTADO_CONCILIACION[d.estado] ?? d.estado, d.etiqueta, d.contraparte,
          d.cuit && d.cuit !== '0' ? d.cuit.replace(/^(\d{2})(\d{8})(\d)$/, '$1-$2-$3') : '', d.sistema ? Number(d.sistema.total) : '', d.detalle.join(' · ')]);
      }
      if (!c.diferencias.length) wd.addRow([c.tipo === 'emitidos' ? 'Ventas (emitidos)' : 'Compras (recibidos)', 'Sin diferencias']);
    }
    wd.getColumn(6).numFmt = FMT_IMPORTE;
  }

  const buffer = await wb.xlsx.writeBuffer();
  const url = URL.createObjectURL(new Blob([buffer], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = `BORRADOR_IVA_Simple_${empresa.nombre_corto.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, '_')}_${periodo}.xlsx`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
}
