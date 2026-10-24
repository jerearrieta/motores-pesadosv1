'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import { api, type FilaLibro, type Operacion, type TotalesLibro } from '@/lib/api';
import { useApp, useDatos } from '@/lib/contexto';
import { exportarExcel, exportarIvaSimple } from '@/lib/exportar';
import { fecha, importe, periodoLargo, pesos, contar } from '@/lib/formato';
import { Icono } from '@/components/Icono';
import { Alerta, Cabecera, Cargando, Stat, useEmpresa } from '@/components/ui';

type Col = [keyof FilaLibro & keyof TotalesLibro, string];
const COLS_CORTAS: Col[] = [['n21', 'Neto 21 %'], ['i21', 'IVA 21 %'], ['n105', 'Neto 10,5 %'], ['i105', 'IVA 10,5 %'], ['no_gravado', 'No gravado'], ['iva', 'IVA total'], ['total', 'Total']];
const COLS_TODAS: Col[] = [['n21', 'Neto 21 %'], ['i21', 'IVA 21 %'], ['n105', 'Neto 10,5 %'], ['i105', 'IVA 10,5 %'], ['n27', 'Neto 27 %'], ['i27', 'IVA 27 %'],
  ['n_otras', 'Neto otras'], ['i_otras', 'IVA otras'], ['n0', 'Neto 0 %'], ['no_gravado', 'No gravado'], ['exento', 'Exento'], ['otros_tributos', 'Otros tributos'],
  ['perc_iva', 'Percepción IVA'], ['perc_iibb', 'Percepción de Ingresos Brutos'], ['iva', 'IVA total'], ['total', 'Total']];

export default function PaginaLibro() {
  const { empresa, avisarError } = useApp();
  const emp = useEmpresa();
  const [periodo, setPeriodo] = useState<string | null>(null);
  const [tab, setTab] = useState<Operacion | 'posicion'>('venta');
  const [todas, setTodas] = useState(false);
  const [exportando, setExportando] = useState(false);

  const periodos = useDatos(() => api.periodos(empresa), [empresa]);
  useEffect(() => {
    if (!periodos.datos?.length) return;
    // por defecto, el último mes con movimientos que no sea futuro
    const actual = new Date().toISOString().slice(0, 7);
    const conDatos = periodos.datos.filter((p) => p.ventas + p.compras > 0 && p.periodo <= actual);
    if (!periodo || !periodos.datos.some((p) => p.periodo === periodo)) setPeriodo((conDatos[0] ?? periodos.datos[0]).periodo);
  }, [periodos.datos, periodo]);

  const pos = periodos.datos?.find((p) => p.periodo === periodo);
  const libro = useDatos(() => (periodo && tab !== 'posicion' ? api.libro(empresa, periodo, tab) : Promise.resolve(null)), [empresa, periodo, tab]);

  async function exportar() {
    if (!periodo) return;
    setExportando(true);
    try { await exportarExcel(emp, periodo); } catch (e) { avisarError(e); } finally { setExportando(false); }
  }

  async function ivaSimple() {
    if (!periodo) return;
    setExportando(true);
    try { await exportarIvaSimple(emp, periodo); } catch (e) { avisarError(e); } finally { setExportando(false); }
  }

  const cols = todas ? COLS_TODAS : COLS_CORTAS;
  const colsLibro = tab === 'compra' || todas ? cols : cols.filter(([k]) => k !== 'perc_iva' && k !== 'perc_iibb');

  return (
    <>
      <Cabecera icono="libro" titulo="Libro de IVA" bajada={<>{emp.razon_social} · CUIT {emp.cuitTexto}{periodo ? ` · ${periodoLargo(periodo)}` : ''}</>}>
      </Cabecera>

      {periodos.error && <Alerta tipo="error">{periodos.error}</Alerta>}
      {!pos ? <Cargando /> : (
        <>
          <div className="stats">
            <Stat color="azul" valor={pesos(pos.debito)} titulo="Débito fiscal" detalle={`IVA de ${contar(pos.ventas, 'comprobante', 'comprobantes')} de venta`} />
            <Stat color="verde" valor={pesos(pos.credito)} titulo="Crédito fiscal" detalle={`IVA de ${contar(pos.compras, 'comprobante', 'comprobantes')} de compra`} />
            <Stat color={pos.saldo >= 0 ? 'naranja' : 'violeta'} valor={pesos(Math.abs(pos.saldo))} titulo={pos.saldo >= 0 ? 'IVA a pagar' : 'Saldo a favor'} detalle="Débito menos crédito" />
            <Stat valor={pos.estado === 'cerrado' ? 'Cerrado' : 'Abierto'} titulo="Estado del período"
              detalle={pos.estado === 'cerrado' ? 'No se puede emitir ni cargar con fecha de este mes' : 'Se puede emitir y cargar compras'} />
          </div>

          <div className="filtros">
            <label className="filtro"><span>Período</span>
              <select className="in" value={periodo ?? ''} onChange={(e) => setPeriodo(e.target.value)} style={{ width: 'auto' }}>
                {periodos.datos?.map((p) => <option key={p.periodo} value={p.periodo}>{p.periodo} · {periodoLargo(p.periodo)}{p.estado === 'cerrado' ? ' (cerrado)' : ''}</option>)}
              </select>
            </label>
            <div className="tabs">
              <button className={tab === 'venta' ? 'on' : ''} onClick={() => setTab('venta')}>Ventas <b>{pos.ventas}</b></button>
              <button className={tab === 'compra' ? 'on' : ''} onClick={() => setTab('compra')}>Compras <b>{pos.compras}</b></button>
              <button className={tab === 'posicion' ? 'on' : ''} onClick={() => setTab('posicion')}>Posición</button>
            </div>
            <div className="filtros-d">
              {tab !== 'posicion' && <button className="btn" onClick={() => setTodas(!todas)}>{todas ? 'Ver menos columnas' : 'Ver todas las columnas'}</button>}
              <button className="btn" onClick={exportar} disabled={exportando}><Icono n="bajar" /> {exportando ? 'Exportando…' : 'Exportar a Excel'}</button>
              <button className="btn" onClick={ivaSimple} disabled={exportando} title="Resumen, ajustes y diferencias con ARCA del período elegido"><Icono n="bajar" /> Resumen para IVA Simple</button>
              <button className="btn" onClick={() => window.print()} title="Imprime el libro que se ve en pantalla; en la ventana de impresión se puede elegir «Guardar como PDF»">Imprimir o guardar en PDF</button>
              <Link className="btn" href="/bandeja-tesoreria/libro-de-iva/cierre-e-historial"><Icono n="candado" /> Cierre del período</Link>
            </div>
          </div>

          {tab === 'posicion' ? (
            <div className="panel">
              <div className="panel-h"><h2>Posición de IVA · {periodoLargo(pos.periodo)}</h2></div>
              <div className="ecuacion">
                <div className="ec-b azul"><span>Débito fiscal</span><b>{pesos(pos.debito)}</b><small>IVA de las ventas</small></div>
                <div className="ec-s">−</div>
                <div className="ec-b verde"><span>Crédito fiscal</span><b>{pesos(pos.credito)}</b><small>IVA de las compras</small></div>
                <div className="ec-s">=</div>
                <div className={`ec-b ${pos.saldo >= 0 ? 'naranja' : 'violeta'}`}><span>{pos.saldo >= 0 ? 'A pagar' : 'Saldo a favor'}</span><b>{pesos(Math.abs(pos.saldo))}</b><small>del período</small></div>
              </div>
              <p className="nota" style={{ textAlign: 'center' }}>
                Percepciones sufridas en el período (informativas, no entran en la cuenta): IVA {pesos(pos.perc_iva)} · Ingresos Brutos {pesos(pos.perc_iibb)}.
              </p>
            </div>
          ) : libro.error ? <Alerta tipo="error">{libro.error}</Alerta> : !libro.datos ? <Cargando /> : (
            <div className="panel flush">
              <div className="panel-h">
                <h2>{tab === 'venta' ? 'Libro IVA Ventas' : 'Libro IVA Compras'} · {periodoLargo(pos.periodo)}</h2>
                <span className="nota">{tab === 'venta' ? 'Por fecha de emisión · los borradores no entran' : 'Por período de imputación · las anuladas no entran'} · las notas de crédito restan</span>
              </div>
              {libro.datos.filas.length === 0 ? <p className="vacio">No hay comprobantes en este período.</p> : (
                <div className="tabla-wrap">
                  <table className="tabla libro">
                    <thead><tr>
                      <th className="comp">Comprobante</th><th>Fecha</th><th>{tab === 'venta' ? 'Cliente' : 'Proveedor'}</th>
                      {colsLibro.map(([k, t]) => <th key={k} className="num">{t}</th>)}
                    </tr></thead>
                    <tbody>
                      {libro.datos.filas.map((f) => (
                        <tr key={f.id}>
                          <th className="comp"><Link href={`/bandeja-tesoreria/${tab === 'venta' ? 'facturas-de-venta/facturas-emitidas' : 'facturas-de-compra'}/${f.id}`} style={{ textDecoration: 'none' }}>
                            <small>{f.tipo_desc}</small><span className="mono">{f.numero}</span></Link></th>
                          <td className="mono nw">{fecha(f.fecha)}</td>
                          <td className="nom">{f.contraparte}<small className="mono">{f.documento} · {f.condicion}</small></td>
                          {colsLibro.map(([k]) => {
                            const v = Number(f[k]);
                            return <td key={k} className={`num${v < 0 ? ' neg' : v === 0 ? ' cero' : ''}${k === 'total' ? ' strong' : ''}`}>{v === 0 ? '—' : importe(v)}</td>;
                          })}
                        </tr>
                      ))}
                    </tbody>
                    <tfoot><tr>
                      <th className="comp">Totales</th><td /><td>{contar(libro.datos.totales.cantidad, 'comprobante', 'comprobantes')}</td>
                      {colsLibro.map(([k]) => <td key={k} className="num">{importe(libro.datos!.totales[k])}</td>)}
                    </tr></tfoot>
                  </table>
                </div>
              )}
              <div className="resumen-libro">
                {tab === 'venta'
                  ? <>Débito fiscal del período: <strong>{pesos(libro.datos.totales.iva)}</strong></>
                  : <>Crédito fiscal del período: <strong>{pesos(libro.datos.totales.iva)}</strong>. Las facturas B y C no dan crédito: su importe va como no gravado.</>}
              </div>
            </div>
          )}
        </>
      )}
    </>
  );
}
