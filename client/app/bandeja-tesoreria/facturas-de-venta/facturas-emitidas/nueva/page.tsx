'use client';

import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense, useEffect, useMemo, useState } from 'react';
import { api, ErrorNegocio, type Calculo } from '@/lib/api';
import { useApp, useDatos } from '@/lib/contexto';
import { hoy, leerNumero, pesos } from '@/lib/formato';
import { Icono } from '@/components/Icono';
import { Alerta, Cabecera, Campo, Cargando, SinPermiso, useEmpresa } from '@/components/ui';

interface Linea { codigo: string; descripcion: string; cantidad: string; precio: string; descuento: string; alicuota_codigo: number; total: string }
const lineaVacia = (): Linea => ({ codigo: '', descripcion: '', cantidad: '1', precio: '', descuento: '', alicuota_codigo: 5, total: '' });
const CONDICIONES_VENTA = ['Contado', 'Cuenta corriente 30 días', 'Cuenta corriente 60 días', 'Transferencia', 'Cheque', 'Tarjeta', 'A convenir'];

export default function Pagina() {
  return <Suspense fallback={<Cargando />}><FormVenta /></Suspense>;
}

function FormVenta() {
  const { empresa, rol, catalogos, puede, avisar, avisarError } = useApp();
  const emp = useEmpresa();
  const router = useRouter();
  const idBorrador = useSearchParams().get('id');
  const clientes = useDatos(() => api.contrapartes('cliente'), []);
  const pvs = catalogos!.puntos_venta.filter((p) => p.empresa_id === empresa);

  const [f, setF] = useState({ punto_venta: pvs[0]?.numero ?? 1, contraparte_id: '', fecha: hoy(), condicion_venta: 'Contado', presupuesto: '', orden_compra: '', remito: '', observaciones: '', modo: 'neto' as 'neto' | 'precio_final' });
  const [lineas, setLineas] = useState<Linea[]>([lineaVacia()]);
  const [calc, setCalc] = useState<Calculo | null>(null);
  const [errorCalc, setErrorCalc] = useState<string | null>(null);
  const [error, setError] = useState<ErrorNegocio | null>(null);
  const [enviando, setEnviando] = useState(false);

  // Editar un borrador: se cargan sus datos
  useEffect(() => {
    if (!idBorrador) return;
    api.comprobante(idBorrador).then((c) => {
      setF({ punto_venta: c.punto_venta, contraparte_id: c.contraparte_id, fecha: c.fecha, condicion_venta: c.condicion_venta, presupuesto: c.presupuesto,
        orden_compra: c.orden_compra, remito: c.remito, observaciones: c.observaciones, modo: c.modo });
      setLineas(c.items.map((i) => ({ codigo: i.codigo, descripcion: i.descripcion, cantidad: String(i.cantidad), precio: String(i.precio_lista),
        descuento: Number(i.descuento) ? String(i.descuento) : '', alicuota_codigo: i.alicuota_codigo, total: c.modo === 'precio_final' ? String(c.total) : '' })));
    }).catch(avisarError);
  }, [idBorrador, avisarError]);

  const cliente = clientes.datos?.find((c) => c.id === f.contraparte_id);
  const letra = catalogos!.condiciones.find((c) => c.codigo === cliente?.condicion_iva)?.letra_venta;

  const lineasApi = useMemo(() => lineas.map((l) => f.modo === 'precio_final'
    ? { descripcion: l.descripcion || 'Venta', total: leerNumero(l.total) ?? l.total, alicuota_codigo: l.alicuota_codigo }
    : { codigo: l.codigo, descripcion: l.descripcion || '(sin descripción)', cantidad: leerNumero(l.cantidad, 4) ?? l.cantidad, precio: leerNumero(l.precio, 4) ?? (l.precio || '0'),
        descuento: leerNumero(l.descuento) ?? (l.descuento || '0'), alicuota_codigo: l.alicuota_codigo }), [lineas, f.modo]);

  // Vista previa de importes: la calcula el server, no se guarda nada
  useEffect(() => {
    const t = setTimeout(() => {
      api.calcular({ operacion: 'venta', modo: f.modo, lineas: lineasApi })
        .then((r) => { setCalc(r); setErrorCalc(null); })
        .catch((e) => { setCalc(null); setErrorCalc(e instanceof ErrorNegocio ? e.detalle : String(e)); });
    }, 300);
    return () => clearTimeout(t);
  }, [lineasApi, f.modo]);

  if (!puede('emitir_venta')) return <><Cabecera icono="recibo" titulo="Nueva factura de venta" /><SinPermiso accion="emitir_venta" /></>;

  const cambiarLinea = (i: number, k: keyof Linea, v: string | number) => setLineas((ls) => ls.map((l, j) => (j === i ? { ...l, [k]: v } : l)));

  async function guardar(emitir: boolean) {
    setEnviando(true); setError(null);
    try {
      const c = await api.guardarVenta(rol, { id: idBorrador, empresa_id: empresa, ...f, lineas: lineasApi }, emitir);
      avisar(emitir ? `Se emitió ${c.etiqueta} por ${pesos(c.total)}.` : 'Se guardó el borrador.');
      router.push(`/bandeja-tesoreria/facturas-de-venta/facturas-emitidas/${c.id}`);
    } catch (e) {
      setError(e instanceof ErrorNegocio ? e : new ErrorNegocio('ERROR', String(e), null));
      window.scrollTo({ top: 0, behavior: 'smooth' });
    } finally { setEnviando(false); }
  }

  return (
    <>
      <Cabecera icono="recibo" titulo={idBorrador ? 'Editar borrador de venta' : 'Factura sin presupuesto de venta'}
        bajada={<>{emp.razon_social} · para ventas de mostrador o trabajos sin presupuesto de venta. Si hay presupuesto, usá «Emitir desde un presupuesto de venta». La letra, el número y los importes los pone el sistema al emitir.</>}>
        <Link className="btn" href="/bandeja-tesoreria/facturas-de-venta/facturas-emitidas">Volver</Link>
      </Cabecera>
      {error && <Alerta tipo="error"><strong>{error.codigo.replace(/_/g, ' ').toLowerCase()}</strong><p>{error.detalle}</p></Alerta>}

      <div className="panel form-p">
        <div className="panel-h"><h2>Datos del comprobante</h2><span className="tag-prueba">PRUEBA</span></div>
        <div className="grid-form">
          <Campo etiqueta="Cliente" ancho error={error?.campo === 'contraparte_id' ? error.detalle : null}
            ayuda={cliente ? (cliente.completo ? <span className="ok-t">{cliente.documento} · {cliente.condicion_desc} · se emite Factura {letra ?? '?'}</span>
              : <span className="mal-t">Faltan datos fiscales: {cliente.faltantes.join(', ')}. Se puede guardar como borrador.</span>) : null}>
            <select className="in" value={f.contraparte_id} onChange={(e) => setF({ ...f, contraparte_id: e.target.value })}>
              <option value="">Elegí un cliente…</option>
              {clientes.datos?.map((c) => <option key={c.id} value={c.id}>{c.nombre}{c.completo ? '' : ' (datos incompletos)'}</option>)}
            </select>
          </Campo>
          <Campo etiqueta="Punto de venta">
            <select className="in" value={f.punto_venta} onChange={(e) => setF({ ...f, punto_venta: Number(e.target.value) })}>
              {pvs.map((p) => <option key={p.numero} value={p.numero}>{String(p.numero).padStart(5, '0')} · {p.descripcion}</option>)}
            </select>
          </Campo>
          <Campo etiqueta="Fecha de emisión" error={error?.campo === 'fecha' ? error.detalle : null}>
            <input className="in" type="date" value={f.fecha} onChange={(e) => setF({ ...f, fecha: e.target.value })} />
          </Campo>
          <Campo etiqueta="Condición de venta">
            <select className="in" value={f.condicion_venta} onChange={(e) => setF({ ...f, condicion_venta: e.target.value })}>
              {CONDICIONES_VENTA.map((c) => <option key={c}>{c}</option>)}
            </select>
          </Campo>
          <Campo etiqueta="Presupuesto de venta (solo como referencia)" ayuda="Opcional. Para facturar las líneas de un presupuesto, usá «Emitir desde un presupuesto de venta»">
            <input className="in" value={f.presupuesto} onChange={(e) => setF({ ...f, presupuesto: e.target.value })} />
          </Campo>
          <Campo etiqueta="Orden de compra del cliente"><input className="in" value={f.orden_compra} onChange={(e) => setF({ ...f, orden_compra: e.target.value })} /></Campo>
          <Campo etiqueta="Remito"><input className="in" value={f.remito} onChange={(e) => setF({ ...f, remito: e.target.value })} /></Campo>
        </div>

        <h3>Detalle</h3>
        <div className="seg grande">
          <button className={`seg-b${f.modo === 'neto' ? ' on' : ''}`} onClick={() => setF({ ...f, modo: 'neto' })}>Precios sin IVA</button>
          <button className={`seg-b${f.modo === 'precio_final' ? ' on' : ''}`} onClick={() => { setF({ ...f, modo: 'precio_final' }); setLineas((ls) => [ls[0]]); }}>Precio final con IVA (mostrador)</button>
        </div>
        <div className="tabla-wrap">
          <table className="tabla lineas">
            <thead><tr>
              {f.modo === 'neto' && <th>Código</th>}<th>Descripción</th>
              {f.modo === 'neto' ? <><th className="num">Cantidad</th><th className="num">Precio de lista (sin IVA)</th><th className="num">Descuento %</th></> : <th className="num">Precio final (con IVA)</th>}
              <th>Alícuota</th><th className="num">Importe sin IVA</th><th />
            </tr></thead>
            <tbody>
              {lineas.map((l, i) => (
                <tr key={i}>
                  {f.modo === 'neto' && <td><input className="in" value={l.codigo} onChange={(e) => cambiarLinea(i, 'codigo', e.target.value)} /></td>}
                  <td><input className="in" value={l.descripcion} placeholder="Descripción" onChange={(e) => cambiarLinea(i, 'descripcion', e.target.value)} /></td>
                  {f.modo === 'neto' ? <>
                    <td className="num"><input className="in num-in" inputMode="decimal" value={l.cantidad} onChange={(e) => cambiarLinea(i, 'cantidad', e.target.value)} /></td>
                    <td className="num"><input className="in num-in" inputMode="decimal" value={l.precio} placeholder="0,00" onChange={(e) => cambiarLinea(i, 'precio', e.target.value)} /></td>
                    <td className="num"><input className="in num-in dto-in" inputMode="decimal" value={l.descuento} placeholder="0" onChange={(e) => cambiarLinea(i, 'descuento', e.target.value)} /></td>
                  </> : <td className="num"><input className="in num-in" inputMode="decimal" value={l.total} placeholder="0,00" onChange={(e) => cambiarLinea(i, 'total', e.target.value)} /></td>}
                  <td><select className="in" value={l.alicuota_codigo} onChange={(e) => cambiarLinea(i, 'alicuota_codigo', Number(e.target.value))}>
                    {catalogos!.alicuotas.map((a) => <option key={a.codigo} value={a.codigo}>{a.descripcion}</option>)}
                  </select></td>
                  <td className="num mono">{calc?.items?.[i] ? pesos(calc.items[i].importe_neto) : '—'}</td>
                  <td>{lineas.length > 1 && <button className="btn ghost chico" aria-label="Quitar línea" onClick={() => setLineas(lineas.filter((_, j) => j !== i))}><Icono n="cruz" t={14} /></button>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {f.modo === 'neto' && <div className="lineas-acc"><button className="btn chico" onClick={() => setLineas([...lineas, lineaVacia()])}><Icono n="mas" t={14} /> Agregar línea</button></div>}

        <div className="totales">
          <div>
            <h3 style={{ marginTop: 0 }}>IVA por alícuota</h3>
            <table className="mini"><thead><tr><th>Alícuota</th><th className="num">Base</th><th className="num">IVA</th></tr></thead>
              <tbody>{calc?.desglose.map((d) => <tr key={d.alicuota_codigo}><td>{String(d.porcentaje).replace('.', ',')} %</td><td className="num">{pesos(d.base)}</td><td className="num">{pesos(d.iva)}</td></tr>)}</tbody>
            </table>
            <p className="nota" style={{ marginTop: 8 }}>El IVA se calcula sobre la suma de netos de cada alícuota y se redondea a centavos.</p>
          </div>
          <dl className="resumen">
            <div><dt>Neto gravado</dt><dd>{pesos(calc?.importes.neto_gravado)}</dd></div>
            <div><dt>IVA</dt><dd>{pesos(calc?.importes.iva)}</dd></div>
            <div className="gr"><dt>Total</dt><dd>{pesos(calc?.importes.total)}</dd></div>
          </dl>
        </div>
        {errorCalc && <p className="campo-msg">{errorCalc}</p>}
      </div>

      <div className="barra-fija">
        <div className="bf-t"><span>Total de la factura</span><b>{pesos(calc?.importes.total)}</b></div>
        <div className="bf-b">
          <button className="btn" disabled={enviando} onClick={() => guardar(false)}>Guardar borrador</button>
          <button className="btn primario" disabled={enviando} onClick={() => guardar(true)}>Emitir</button>
        </div>
      </div>
    </>
  );
}
