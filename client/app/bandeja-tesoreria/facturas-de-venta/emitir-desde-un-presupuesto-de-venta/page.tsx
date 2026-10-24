'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useMemo, useState } from 'react';
import { api, ErrorNegocio, type Calculo, type Presupuesto } from '@/lib/api';
import { useApp, useDatos } from '@/lib/contexto';
import { contar, fecha, hoy, importe, pesos } from '@/lib/formato';
import { RUTAS } from '@/lib/rutas';
import { Icono } from '@/components/Icono';
import { Alerta, Cabecera, Campo, Cargando, useEmpresa } from '@/components/ui';

const CONDICIONES_VENTA = ['Contado', 'Cuenta corriente 30 días', 'Cuenta corriente 60 días', 'Transferencia', 'Cheque', 'A convenir'];
const moneda = (m: string) => (m === 'USD' ? 'US$' : '$');

/**
 * Emitir desde un presupuesto de venta tildando líneas (facturación parcial: cada línea se factura una sola vez).
 * Las líneas, la conversión de dólares a pesos y los importes los arma el servidor; acá solo se eligen y se muestran.
 */
export default function EmitirDesdePresupuesto() {
  const { empresa, rol, catalogos, puede, avisar } = useApp();
  const emp = useEmpresa();
  const router = useRouter();
  const lista = useDatos(() => api.presupuestos(empresa), [empresa]);
  const pvs = catalogos!.puntos_venta.filter((p) => p.empresa_id === empresa);
  const [elegido, setElegido] = useState<string | null>(null);
  const [tildadas, setTildadas] = useState<string[]>([]);
  const [f, setF] = useState({ punto_venta: pvs[0]?.numero ?? 1, fecha: hoy(), condicion_venta: 'Contado', orden_compra: '', remito: '', observaciones: '' });
  const [emitirEn, setEmitirEn] = useState<'pesos' | 'dolares'>('pesos');
  const [cotizacion, setCotizacion] = useState('');
  const [calc, setCalc] = useState<Calculo | null>(null);
  const [error, setError] = useState<ErrorNegocio | null>(null);
  const [enviando, setEnviando] = useState(false);

  const p: Presupuesto | undefined = lista.datos?.find((x) => x.id === elegido);
  const pendientes = useMemo(() => p?.lineas.filter((l) => !l.facturada) ?? [], [p]);

  useEffect(() => { setElegido(null); setF((x) => ({ ...x, punto_venta: pvs[0]?.numero ?? 1 })); }, [empresa]); // eslint-disable-line react-hooks/exhaustive-deps

  function elegir(x: Presupuesto) {
    setElegido(x.id);
    setTildadas(x.lineas.filter((l) => !l.facturada).map((l) => l.id));
    setEmitirEn('pesos');
    setCotizacion(String(x.cotizacion));
    setF((y) => ({ ...y, condicion_venta: CONDICIONES_VENTA.includes(x.condiciones) ? x.condiciones : y.condicion_venta }));
    setError(null);
    // el formulario aparece debajo de las tarjetas: se lleva la vista hasta él para que se note que pasó algo
    setTimeout(() => document.getElementById('form-emitir')?.scrollIntoView({ behavior: 'smooth', block: 'start' }), 60);
  }

  // Vista previa: el servidor arma las líneas (y las pasa a pesos si hace falta) y calcula los importes
  useEffect(() => {
    setCalc(null);
    if (!p || !tildadas.length) return;
    let vivo = true;
    const t = setTimeout(() => {
      api.prepararLineasPresupuesto(p.id, tildadas, emitirEn, cotizacion)
        .then((lineas) => api.calcular({ operacion: 'venta', modo: 'neto', lineas }))
        .then((c) => { if (vivo) setCalc(c); })
        .catch(() => { if (vivo) setCalc(null); });
    }, 250);
    return () => { vivo = false; clearTimeout(t); };
  }, [p, tildadas, emitirEn, cotizacion]);

  async function guardar(emitir: boolean) {
    if (!p) return;
    setEnviando(true); setError(null);
    try {
      const c = await api.guardarVenta(rol, {
        empresa_id: empresa, contraparte_id: p.cliente.id, ...f, modo: 'neto', presupuesto_id: p.id, presupuesto_lineas: tildadas,
        emitir_en: emitirEn, cotizacion,
      }, emitir);
      avisar(emitir ? `Se emitió ${c.etiqueta} por ${pesos(c.total)}${c.moneda === 'USD' ? ' (en dólares)' : ''}.` : 'Se guardó el borrador.');
      router.push(`${RUTAS.ventas}/${c.id}`);
    } catch (e) {
      setError(e instanceof ErrorNegocio ? e : new ErrorNegocio('ERROR', String(e), null));
      window.scrollTo({ top: 0, behavior: 'smooth' });
    } finally { setEnviando(false); }
  }

  const enDolares = p?.moneda === 'USD';
  const simbolo = enDolares && emitirEn === 'dolares' ? 'US$' : '$';

  return (
    <>
      <Cabecera icono="recibo" titulo="Emitir desde un presupuesto de venta"
        bajada={<>Presupuestos de venta de {emp.razon_social}: tildá las líneas que se facturan ahora; el resto queda para otra factura.</>} />
      {!puede('emitir_venta') && <div className="rol-aviso"><Icono n="info" /> Con este rol se pueden mirar los presupuestos, pero no guardar ni emitir.</div>}
      {lista.error && <Alerta tipo="error">{lista.error}</Alerta>}
      {!lista.datos ? <Cargando /> : !lista.datos.length ? (
        <section className="panel vacio-g"><Icono n="recibo" t={34} /><h2>No hay presupuestos de venta</h2><p>Esta empresa no tiene presupuestos de venta cargados.</p></section>
      ) : (
        <div className="presupuestos-grid">
          {lista.datos.map((x) => {
            const nfact = x.lineas.filter((l) => l.facturada).length;
            const activo = x.id === elegido;
            return (
              <article key={x.id} className={`card-pres${activo ? ' sel' : ''}${x.facturable ? '' : ' dim'}`}>
                <div className="cp-h"><span className="codigo">{x.numero}</span>
                  <span className={`pill ${x.estado === 'cancelado' || x.estado === 'perdido' ? 'rojo' : x.facturable ? 'verde' : ''}`}>{x.estado_texto}</span></div>
                <div className="cp-c"><strong>{x.cliente.nombre}</strong>
                  {x.cliente.completo ? <span className="pill verde">Datos fiscales completos</span> : <span className="pill rojo">Faltan datos fiscales</span>}</div>
                <p className="cp-d">{x.descripcion}</p>
                <dl className="datos">
                  <div><dt>Fecha</dt><dd>{fecha(x.fecha)}</dd></div>
                  <div><dt>Moneda</dt><dd>{x.moneda === 'USD' ? 'Dólares' : 'Pesos'}</dd></div>
                  <div><dt>Total con IVA</dt><dd>{moneda(x.moneda)} {importe(x.importes.total)}</dd></div>
                  <div><dt>Facturado</dt><dd>{nfact} de {contar(x.lineas.length, 'línea', 'líneas')}</dd></div>
                </dl>
                {x.estado === 'entregado' && nfact < x.lineas.length && (
                  <p className="cp-alerta"><Icono n="alerta" t={14} /> Entregado con líneas sin facturar: los repuestos se facturan hasta fin del mes de la entrega (RG 5866).</p>
                )}
                {!x.facturable ? <p className="cp-no"><Icono n="candado" t={14} /> No se factura: está «{x.estado_texto}».</p>
                  : nfact >= x.lineas.length ? <p className="cp-no"><Icono n="tilde" t={14} /> Facturado completo.</p>
                  : <button className={`btn bloque${activo ? '' : ' primario'}`} onClick={() => elegir(x)}>{activo ? 'Seleccionado' : <>Facturar <Icono n="flechaR" t={15} /></>}</button>}
              </article>
            );
          })}
        </div>
      )}

      {p && (
        <div className="panel form-p" id="form-emitir" style={{ marginTop: 18, scrollMarginTop: 16 }}>
          <div className="panel-h"><h2>Factura del presupuesto de venta {p.numero}</h2><span className="tag-prueba">PRUEBA</span></div>
          {error && <Alerta tipo="error"><strong>{error.codigo.replace(/_/g, ' ').toLowerCase()}</strong><p>{error.detalle}</p></Alerta>}
          {!p.cliente.completo && (
            <Alerta tipo="aviso">El cliente «{p.cliente.nombre}» no tiene datos fiscales completos ({p.cliente.faltantes.join(', ')}): se puede guardar el borrador, pero no emitir.
              {' '}<Link className="btn chico" href="/clientes">Completar datos fiscales</Link></Alerta>
          )}
          <div className="grid-form">
            <Campo etiqueta="Punto de venta">
              <select className="in" value={f.punto_venta} onChange={(e) => setF({ ...f, punto_venta: Number(e.target.value) })}>
                {pvs.map((x) => <option key={x.numero} value={x.numero}>{String(x.numero).padStart(5, '0')} · {x.descripcion}</option>)}
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
            <Campo etiqueta="Orden de compra del cliente"><input className="in" value={f.orden_compra} onChange={(e) => setF({ ...f, orden_compra: e.target.value })} /></Campo>
            <Campo etiqueta="Remito"><input className="in" value={f.remito} onChange={(e) => setF({ ...f, remito: e.target.value })} /></Campo>
            {enDolares && (
              <>
                <Campo etiqueta="Emitir en">
                  <select className="in" value={emitirEn} onChange={(e) => setEmitirEn(e.target.value as 'pesos' | 'dolares')}>
                    <option value="pesos">Pesos, con equivalencia en dólares</option>
                    <option value="dolares">Dólares</option>
                  </select>
                </Campo>
                <Campo etiqueta="Cotización (pesos por dólar)" error={error?.campo === 'cotizacion' ? error.detalle : null}>
                  <input className="in num-in" inputMode="decimal" value={cotizacion} onChange={(e) => setCotizacion(e.target.value.replace(',', '.'))} />
                </Campo>
              </>
            )}
          </div>

          <h3>Líneas del presupuesto de venta</h3>
          {!tildadas.length && <Alerta tipo="aviso">Tildá la casilla de cada línea que querés facturar ahora. Las que no tildes quedan para otra factura.</Alerta>}
          <div className="tabla-wrap">
            <table className="tabla lineas">
              <thead><tr><th className="chk"><span className="sr">Facturar</span></th><th>Código</th><th>Descripción</th><th className="num">Cantidad</th>
                <th className="num">Precio de lista (sin IVA)</th><th className="num">Descuento %</th><th>Alícuota</th><th className="num">Neto</th></tr></thead>
              <tbody>
                {p.lineas.map((l) => (
                  <tr key={l.id} className={l.facturada ? 'ya' : ''}>
                    <td className="chk">{!l.facturada && (
                      <input type="checkbox" aria-label={`Facturar ${l.descripcion}`} checked={tildadas.includes(l.id)}
                        onChange={(e) => setTildadas(e.target.checked ? [...tildadas, l.id] : tildadas.filter((x) => x !== l.id))} />
                    )}</td>
                    <td className="mono">{l.codigo}</td>
                    <td>{l.descripcion}{l.facturada && <small className="ya-t">Ya está en {l.facturada.etiqueta}</small>}</td>
                    <td className="num">{importe(l.cantidad).replace(/,00$/, '')}</td>
                    <td className="num">{moneda(p.moneda)} {importe(l.precio)}</td>
                    <td className="num">{Number(l.descuento) ? String(l.descuento).replace('.', ',') : '—'}</td>
                    <td>{catalogos!.alicuotas.find((a) => a.codigo === l.alicuota_codigo)?.descripcion}</td>
                    <td className="num">{moneda(p.moneda)} {importe(l.neto)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {enDolares && emitirEn === 'pesos' && <p className="nota">Cada precio se pasa a pesos con la cotización, y la línea dice «EQUIVALE A DOLARES U$D …», como en el modelo de factura de la empresa.</p>}

          <div className="totales">
            <div>
              <h3 style={{ marginTop: 0 }}>IVA por alícuota</h3>
              <table className="mini"><thead><tr><th>Alícuota</th><th className="num">Base</th><th className="num">IVA</th></tr></thead>
                <tbody>{calc?.desglose.map((d) => <tr key={d.alicuota_codigo}><td>{String(d.porcentaje).replace('.', ',')} %</td>
                  <td className="num">{simbolo} {importe(d.base)}</td><td className="num">{simbolo} {importe(d.iva)}</td></tr>)}</tbody>
              </table>
            </div>
            <dl className="resumen">
              <div><dt>Neto gravado</dt><dd>{simbolo} {importe(calc?.importes.neto_gravado)}</dd></div>
              <div><dt>IVA</dt><dd>{simbolo} {importe(calc?.importes.iva)}</dd></div>
              <div className="gr"><dt>Total</dt><dd>{simbolo} {importe(calc?.importes.total)}</dd></div>
            </dl>
          </div>
          {pendientes.length > tildadas.length && tildadas.length > 0 && (
            <p className="nota">Quedan {contar(pendientes.length - tildadas.length, 'línea', 'líneas')} sin facturar en este presupuesto de venta.</p>
          )}
          <div className="fila-b">
            <button className="btn" disabled={enviando || !tildadas.length || !puede('emitir_venta')} onClick={() => guardar(false)}>Guardar borrador</button>
            <button className="btn primario" disabled={enviando || !tildadas.length || !puede('emitir_venta') || !p.cliente.completo} onClick={() => guardar(true)}>Emitir sin CAE</button>
          </div>
          <p className="nota">Esta factura se emite sin CAE: no tiene validez fiscal.</p>
        </div>
      )}
    </>
  );
}
