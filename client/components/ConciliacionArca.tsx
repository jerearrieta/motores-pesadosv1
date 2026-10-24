'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState, type ChangeEvent } from 'react';
import { api, type ComprobanteArca, type EstadoConciliacion, type FilaConciliacion, type ResultadoConciliacion, type TipoArchivoArca } from '@/lib/api';
import { useApp, useDatos } from '@/lib/contexto';
import { contar, cuit, fecha, periodoLargo, pesos } from '@/lib/formato';
import { RUTAS } from '@/lib/rutas';
import { exportarIvaSimple } from '@/lib/exportar';
import { Alerta } from './ui';
import { Icono } from './Icono';

const ESTADOS_CONC: Record<EstadoConciliacion, [string, string]> = {
  coincide: ['Coincide', 'verde'], difiere: ['Difiere', 'naranja'], falta_sistema: ['Falta en el sistema', 'azul'],
  falta_arca: ['Falta en ARCA', 'rojo'], anulada_sistema: ['Anulada en el sistema', 'rojo'], en_borrador: ['En borrador', ''],
};

/** Clave de sessionStorage con los datos de ARCA para «Cargar a mano» (así el CUIT no viaja en la dirección). */
export const PRECARGA_ARCA = 'precarga-arca';

/** Texto de una celda de Excel tal como lo leería el servidor. */
function celda(v: unknown): string {
  if (v == null) return '';
  if (v instanceof Date) return `${String(v.getUTCDate()).padStart(2, '0')}/${String(v.getUTCMonth() + 1).padStart(2, '0')}/${v.getUTCFullYear()}`;
  if (typeof v === 'number') return Number.isInteger(v) ? String(v) : v.toFixed(2);
  if (typeof v === 'object') {
    const o = v as { text?: string; result?: unknown; richText?: { text: string }[] };
    if (o.richText) return o.richText.map((x) => x.text).join('');
    if (o.result !== undefined) return celda(o.result);
    if (o.text !== undefined) return String(o.text);
  }
  return String(v);
}

/** CSV tal cual; un Excel (.xlsx) se pasa a CSV con punto y coma, con la primera hoja. */
async function leerArchivo(archivo: File): Promise<string> {
  if (!/\.xlsx$/i.test(archivo.name)) return archivo.text();
  const ExcelJS = (await import('exceljs')).default;
  const libro = new ExcelJS.Workbook();
  await libro.xlsx.load(await archivo.arrayBuffer());
  const filas: string[] = [];
  libro.worksheets[0]?.eachRow({ includeEmpty: false }, (fila) => {
    const valores = (fila.values as unknown[]).slice(1).map(celda);
    filas.push(valores.map((x) => (/[;"\r\n]/.test(x) ? `"${x.replace(/"/g, '""')}"` : x)).join(';'));
  });
  return filas.join('\r\n');
}

function descargar(nombre: string, texto: string) {
  const url = URL.createObjectURL(new Blob([texto], { type: 'text/csv;charset=utf-8' }));
  const a = document.createElement('a');
  a.href = url; a.download = nombre; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

/**
 * Conciliación con «Mis Comprobantes» de ARCA (US-064 y US-111). El servidor lee el archivo, compara y guarda la conciliación;
 * acá solo se muestra. Con tipoFijo='recibidos' es la sección «Importar desde ARCA» de Facturas de compra.
 */
export function ConciliacionArca({ tipoFijo }: { tipoFijo?: TipoArchivoArca }) {
  const { empresa, rol, puede, avisar, avisarError, recargarBorradores, catalogos } = useApp();
  const router = useRouter();
  const emp = catalogos?.empresas.find((e) => e.id === empresa);
  const [tipo, setTipo] = useState<TipoArchivoArca>(tipoFijo ?? 'recibidos');
  const [periodo, setPeriodo] = useState<string | null>(null);
  const [archivo, setArchivo] = useState<{ nombre: string; texto: string } | null>(null);
  const [res, setRes] = useState<ResultadoConciliacion | null>(null);
  const [seleccion, setSeleccion] = useState<Set<number>>(new Set());
  const [filtro, setFiltro] = useState<EstadoConciliacion | 'todos'>('todos');
  const [mensaje, setMensaje] = useState<{ tipo: 'info' | 'aviso' | 'error'; texto: string } | null>(null);
  const [trabajando, setTrabajando] = useState(false);
  const recibidos = tipo === 'recibidos';

  const periodos = useDatos(() => api.periodos(empresa), [empresa]);
  useEffect(() => {
    if (!periodos.datos?.length) return;
    const actual = new Date().toISOString().slice(0, 7);
    const conDatos = periodos.datos.filter((p) => p.ventas + p.compras > 0 && p.periodo <= actual);
    if (!periodo || !periodos.datos.some((p) => p.periodo === periodo)) setPeriodo((conDatos[0] ?? periodos.datos[0]).periodo);
  }, [periodos.datos, periodo]);

  // Al cambiar de empresa, período o archivo de ARCA, la comparación anterior deja de valer
  useEffect(() => { setRes(null); setArchivo(null); setSeleccion(new Set()); setMensaje(null); setFiltro('todos'); }, [empresa, periodo, tipo]);

  async function conciliar(nombre: string, texto: string) {
    if (!periodo) return;
    setTrabajando(true);
    try {
      const r = await api.conciliarArca(rol, empresa, periodo, tipo, nombre, texto);
      setArchivo({ nombre, texto });
      setRes(r);
      setSeleccion(new Set((r.conciliacion?.filas ?? []).map((f, i) => (f.estado === 'falta_sistema' && f.importable ? i : -1)).filter((i) => i >= 0)));
    } catch (e) { avisarError(e); } finally { setTrabajando(false); }
  }

  async function subir(e: ChangeEvent<HTMLInputElement>) {
    const a = e.target.files?.[0];
    e.target.value = '';
    if (!a) return;
    setMensaje(null);
    try { await conciliar(a.name, await leerArchivo(a)); } catch (err) { avisarError(err); }
  }

  async function ejemplo(soloDescargar: boolean) {
    if (!periodo) return;
    try {
      const texto = await api.archivoEjemploArca(empresa, periodo, tipo);
      const nombre = `ejemplo-mis-comprobantes-${recibidos ? 'recibidos' : 'emitidos'}-${periodo}.csv`;
      if (soloDescargar) descargar(nombre, texto);
      else { setMensaje(null); await conciliar(nombre, texto); }
    } catch (e) { avisarError(e); }
  }

  async function importar() {
    if (!res?.conciliacion || !archivo) return;
    const elegidos = res.conciliacion.filas.filter((f, i) => seleccion.has(i) && f.arca).map((f) => f.arca as ComprobanteArca);
    setTrabajando(true);
    try {
      const r = await api.importarDesdeArca(rol, empresa, tipo, elegidos);
      setMensaje({ tipo: r.errores.length ? 'aviso' : 'info', texto: `Se importaron ${contar(r.creados.length, 'comprobante', 'comprobantes')}`
        + (recibidos ? ' como borrador.' : ' como histórico.') + (r.errores.length ? ` Revisar: ${r.errores.join(' ')}` : '') });
      recargarBorradores();
      await conciliar(archivo.nombre, archivo.texto);
    } catch (e) { avisarError(e); } finally { setTrabajando(false); }
  }

  async function confirmar() {
    if (!archivo) return;
    setTrabajando(true);
    try {
      const r = await api.confirmarImportadas(rol, empresa);
      setMensaje({ tipo: r.pendientes.length ? 'aviso' : 'info', texto: `Se ${r.ok.length === 1 ? 'confirmó' : 'confirmaron'} ${contar(r.ok.length, 'compra importada', 'compras importadas')}.`
        + (r.pendientes.length ? ` Quedan en borrador: ${r.pendientes.map((p) => `${p.etiqueta} (${p.motivo})`).join('; ')}.` : '') });
      recargarBorradores();
      await conciliar(archivo.nombre, archivo.texto);
    } catch (e) { avisarError(e); } finally { setTrabajando(false); }
  }

  // El período del Excel es el de esta pantalla
  async function ivaSimple() {
    if (!periodo || !emp) return;
    try { await exportarIvaSimple(emp, periodo); } catch (e) { avisarError(e); }
  }

  function cargarAMano(f: FilaConciliacion) {
    if (!f.arca) return;
    try { sessionStorage.setItem(PRECARGA_ARCA, JSON.stringify(f.arca)); } catch { /* sin almacenamiento: el formulario sale vacío */ }
    router.push(`${RUTAS.cargarCompra}?desde_arca=1`);
  }

  const conc = res?.conciliacion ?? null;
  const filas = (conc?.filas ?? []).map((f, i) => ({ f, i })).filter(({ f }) => filtro === 'todos' || f.estado === filtro);
  const importables = (conc?.filas ?? []).filter((f) => f.estado === 'falta_sistema' && f.importable).length;
  const borradoresArca = (conc?.filas ?? []).filter((f) => f.sistema?.estado === 'borrador').length;
  const nombreEmpresa = emp?.nombre_corto ?? '';
  const puedeImportar = puede('importar_arca');

  return (
    <>
      <div className="filtros">
        {!tipoFijo && (
          <div className="tabs" role="group" aria-label="Archivo de ARCA">
            <button className={recibidos ? 'on' : ''} aria-pressed={recibidos} onClick={() => setTipo('recibidos')}>Compras (recibidos)</button>
            <button className={!recibidos ? 'on' : ''} aria-pressed={!recibidos} onClick={() => setTipo('emitidos')}>Ventas (emitidos)</button>
          </div>
        )}
        <label className="filtro"><span>Período</span>
          <select className="in" value={periodo ?? ''} onChange={(e) => setPeriodo(e.target.value)} style={{ width: 'auto' }}>
            {periodos.datos?.map((p) => <option key={p.periodo} value={p.periodo}>{periodoLargo(p.periodo)}</option>)}
          </select>
        </label>
        {tipoFijo && <p className="nota">Facturas recibidas según «Mis Comprobantes» de ARCA. Las ventas emitidas se concilian en Libro de IVA → Conciliación con ARCA.</p>}
      </div>

      <section className="panel">
        <div className="pasos-arca">
          <div><b>1</b><p>En ARCA entrá a <strong>Mis Comprobantes</strong>, elegí <strong>{recibidos ? 'Recibidos' : 'Emitidos'}</strong>, el CUIT de <strong>{nombreEmpresa}</strong> y el período, y descargá el archivo (CSV o Excel).</p></div>
          <div><b>2</b><p>Subilo acá. El sistema compara comprobante por comprobante con lo cargado y marca qué coincide, qué difiere y qué falta.</p></div>
          <div><b>3</b><p>{recibidos ? 'Importá las facturas que faltan: quedan como borrador y se confirman de una vez.' : 'Importá las facturas emitidas con el sistema anterior como histórico, para que el libro de ventas quede completo.'}</p></div>
          <div><b>4</b><p>Exportá el resumen y los ajustes para que el contador liquide en <strong>IVA Simple</strong> sin cargar nada a mano.</p></div>
        </div>
        <div className="filtros" style={{ marginTop: 14, marginBottom: 6 }}>
          <label className={`btn primario${trabajando || !periodo ? ' deshabilitado' : ''}`} htmlFor="archivo-arca"><Icono n="subir" t={16} /> Subir archivo de ARCA</label>
          <input type="file" id="archivo-arca" accept=".csv,.txt,.xlsx" hidden onChange={subir} disabled={trabajando || !periodo} />
          <button className="btn" onClick={() => ejemplo(false)} disabled={trabajando || !periodo}><Icono n="chispa" t={16} /> Probar con un archivo de ejemplo</button>
          <button className="btn ghost" onClick={() => ejemplo(true)} disabled={!periodo}><Icono n="bajar" t={16} /> Descargar el archivo de ejemplo</button>
        </div>
        <p className="nota">El archivo de ejemplo es ficticio y tiene el formato de «Mis Comprobantes». En el ambiente de prueba no subas archivos reales. El Excel tiene que ser .xlsx (el .xls viejo no se puede leer: guardalo como .xlsx o CSV).</p>
      </section>

      {trabajando && <p className="cargando">Procesando…</p>}
      {mensaje && <Alerta tipo={mensaje.tipo}>{mensaje.texto}</Alerta>}

      {res && !conc && (
        <Alerta tipo="error"><strong>No se pudo leer «{archivo?.nombre}».</strong> {res.lectura.errores.join(' ')}</Alerta>
      )}

      {conc && (
        <>
          {res!.lectura.errores.length > 0 && <Alerta tipo="aviso">Algunas filas no se pudieron leer: {res!.lectura.errores.join(' ')}</Alerta>}
          <div className="stats chicas">
            <button className={`stat filtro-stat${filtro === 'todos' ? ' activo' : ''}`} onClick={() => setFiltro('todos')}><b>{conc.filas.length}</b><span>Todos</span></button>
            {(['coincide', 'difiere', 'falta_sistema', 'falta_arca', 'en_borrador', 'anulada_sistema'] as EstadoConciliacion[])
              .filter((e) => e !== 'en_borrador' && e !== 'anulada_sistema' || conc.resumen[e] > 0)
              .map((e) => (
                <button key={e} className={`stat ${ESTADOS_CONC[e][1]} filtro-stat${filtro === e ? ' activo' : ''}`} onClick={() => setFiltro(e)} aria-pressed={filtro === e}>
                  <b>{conc.resumen[e]}</b><span>{ESTADOS_CONC[e][0]}</span>
                </button>
              ))}
          </div>
          {conc.fuera > 0 && <p className="nota">{conc.fuera === 1 ? '1 comprobante del archivo es de otro período y no se comparó.' : `${conc.fuera} comprobantes del archivo son de otro período y no se compararon.`}</p>}

          <section className="panel flush">
            <div className="panel-h"><h2>Totales de {periodoLargo(periodo ?? '')}</h2>
              <span className="nota">Archivo: {archivo?.nombre} · {res!.lectura.detalle_alicuotas ? 'trae detalle por alícuota' : 'formato sin detalle por alícuota'}</span></div>
            <div className="tabla-wrap"><table className="tabla">
              <thead><tr><th></th><th className="num">Neto, no gravado y exento</th><th className="num">IVA</th><th className="num">Total</th></tr></thead>
              <tbody>
                <tr><th scope="row">Según ARCA</th><td className="num">{pesos(conc.tot_arca.neto)}</td><td className="num">{pesos(conc.tot_arca.iva)}</td><td className="num">{pesos(conc.tot_arca.total)}</td></tr>
                <tr><th scope="row">Según el libro del sistema</th><td className="num">{pesos(conc.tot_sistema.neto)}</td><td className="num">{pesos(conc.tot_sistema.iva)}</td><td className="num">{pesos(conc.tot_sistema.total)}</td></tr>
              </tbody>
              <tfoot><tr><th scope="row">Diferencia</th>
                {(['neto', 'iva', 'total'] as const).map((k) => {
                  const d = Math.round((Number(conc.tot_arca[k]) - Number(conc.tot_sistema[k])) * 100) / 100;
                  return <td key={k} className={`num${d ? ' neg' : ''}`}>{pesos(d)}</td>;
                })}
              </tr></tfoot>
            </table></div>
          </section>

          <section className="panel flush">
            <div className="panel-h"><h2>Comprobante por comprobante</h2>
              <button className="btn chico ghost" onClick={ivaSimple} disabled={trabajando}><Icono n="bajar" t={15} /> Resumen y ajustes para IVA Simple</button>
              {importables > 0 && (
                <button className="btn primario chico" onClick={importar} disabled={trabajando || !seleccion.size || !puedeImportar}
                  title={puedeImportar ? undefined : 'Tu rol no puede importar comprobantes desde ARCA'}>
                  <Icono n="bajar" t={15} /> {recibidos ? 'Importar como borrador' : 'Importar como histórico'} ({seleccion.size})
                </button>
              )}
              {recibidos && borradoresArca > 0 && (
                <button className="btn chico" onClick={confirmar} disabled={trabajando || !puede('cargar_compra')}
                  title={puede('cargar_compra') ? undefined : 'Tu rol no puede confirmar compras'}>
                  <Icono n="tilde" t={15} /> Confirmar las importadas completas ({borradoresArca})
                </button>
              )}
            </div>
            <div className="tabla-wrap"><table className="tabla filas">
              <thead><tr><th className="chk"><span className="sr">Importar</span></th><th>Estado</th><th>Comprobante</th><th>{recibidos ? 'Proveedor' : 'Cliente'}</th>
                <th>Fecha</th><th className="num">Total ARCA</th><th className="num">Total sistema</th><th>Detalle</th></tr></thead>
              <tbody>
                {filas.map(({ f, i }) => (
                  <tr key={i}>
                    <td className="chk">{f.estado === 'falta_sistema' && f.importable && (
                      <input type="checkbox" checked={seleccion.has(i)} aria-label={`Importar ${f.etiqueta}`} disabled={!puedeImportar}
                        onChange={(e) => { const s = new Set(seleccion); if (e.target.checked) s.add(i); else s.delete(i); setSeleccion(s); }} />
                    )}</td>
                    <td><span className={`pill ${ESTADOS_CONC[f.estado][1]}`}>{ESTADOS_CONC[f.estado][0]}</span></td>
                    <td><strong>{f.etiqueta.replace(/\s+\S+$/, '')}</strong><small className="mono nw">{f.etiqueta.split(' ').pop()}</small>
                      {f.arca?.cae && <small className="mono nw">Autorización {f.arca.cae}</small>}</td>
                    <td>{f.contraparte}<small className="mono nw">{f.cuit && f.cuit !== '0' ? `CUIT ${cuit(f.cuit)}` : ''}</small></td>
                    <td className="mono">{fecha(f.arca?.fecha ?? f.sistema?.fecha)}</td>
                    <td className="num">{f.arca ? pesos(f.arca.total) : '—'}</td>
                    <td className="num">{f.sistema ? pesos(f.sistema.total) : '—'}</td>
                    <td className="det-conc">
                      {f.detalle.length ? f.detalle.map((d) => <span key={d}>{d}</span>) : <span className="nota">Sin diferencias</span>}
                      {f.sistema ? <Link className="btn chico det-acc" href={`${recibidos ? RUTAS.compras : RUTAS.ventas}/${f.sistema.id}`}>Ver el comprobante</Link>
                        : recibidos && !f.importable && puede('cargar_compra') ? <button className="btn chico det-acc" onClick={() => cargarAMano(f)}>Cargar a mano</button> : null}
                    </td>
                  </tr>
                ))}
                {!filas.length && <tr><td colSpan={8} className="vacio">No hay comprobantes con ese filtro.</td></tr>}
              </tbody>
            </table></div>
          </section>
        </>
      )}

      {!res && !trabajando && (
        <section className="panel vacio-g"><Icono n="conciliar" t={34} /><h2>Todavía no subiste un archivo</h2>
          <p>Probá con el archivo de ejemplo para ver cómo funciona: tiene facturas que coinciden, una con una diferencia y otras que faltan cargar.</p></section>
      )}
    </>
  );
}
