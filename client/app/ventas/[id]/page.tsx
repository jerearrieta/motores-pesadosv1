'use client';

import Link from 'next/link';
import { useParams, useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { api, ErrorNegocio, type Calculo, type Comprobante } from '@/lib/api';
import { useApp, useDatos } from '@/lib/contexto';
import { fecha, fechaHora, hoy, leerNumero, pesos } from '@/lib/formato';
import { Icono } from '@/components/Icono';
import { Papel } from '@/components/Papel';
import { Alerta, Cabecera, Campo, Cargando, Estado, Modal } from '@/components/ui';

export default function DetalleVenta() {
  const { id } = useParams<{ id: string }>();
  const { rol, catalogos, puede, avisar, avisarError } = useApp();
  const router = useRouter();
  const d = useDatos(() => api.comprobante(id), [id]);
  const [nota, setNota] = useState<'credito' | 'debito' | null>(null);
  const c = d.datos;

  if (d.error) return <Alerta tipo="error">{d.error}</Alerta>;
  if (!c) return <Cargando />;

  async function borrar() {
    if (!confirm('¿Borrar este borrador? No queda en el libro.')) return;
    try { await api.eliminarBorrador(rol, c!.id); avisar('Se borró el borrador.'); router.push('/ventas'); } catch (e) { avisarError(e); }
  }

  return (
    <>
      <Cabecera icono="recibo" titulo={c.estado === 'borrador' ? `Borrador · ${c.tipo_desc}` : c.etiqueta}
        bajada={<>{c.contraparte_razon} · {fecha(c.fecha)} · <Estado estado={c.estado} /></>}>
        <Link className="btn no-print" href="/ventas">Volver</Link>
        <button className="btn no-print" onClick={() => window.print()}><Icono n="archivo" /> Imprimir</button>
      </Cabecera>

      <div className="no-print">
        {c.estado === 'borrador' && (
          <Alerta tipo="aviso">
            <strong>Es un borrador:</strong> todavía no tiene número y no entra en el libro.
            <div className="fila-b">
              {puede('emitir_venta') && <Link className="btn primario chico" href={`/ventas/nueva?id=${c.id}`}><Icono n="lapiz" t={14} /> Editar y emitir</Link>}
              {puede('emitir_venta') && <button className="btn peligro chico" onClick={borrar}><Icono n="basura" t={14} /> Borrar borrador</button>}
            </div>
          </Alerta>
        )}
        {c.estado !== 'borrador' && c.clase === 'factura' && (
          <div className="panel">
            <div className="panel-h"><h2>Correcciones</h2><span className="nota">Una factura emitida no se edita ni se borra: se corrige con una nota.</span></div>
            {c.notas.length > 0 && (
              <ul className="lista-n" style={{ marginBottom: 12 }}>
                {c.notas.map((n) => <li key={n.id}><Link href={`/ventas/${n.id}`}>{n.etiqueta}</Link> · {fecha(n.fecha)} · {pesos(n.total)}</li>)}
              </ul>
            )}
            {puede('emitir_nota_venta') ? (
              <div className="fila-b">
                <button className="btn" onClick={() => setNota('credito')}>Nota de crédito</button>
                <button className="btn" onClick={() => setNota('debito')}>Nota de débito</button>
                <span className="nota">Disponible para notas de crédito: {pesos(c.nc_disponible)}</span>
              </div>
            ) : <p className="nota">Las notas las emite Administración.</p>}
          </div>
        )}
      </div>

      <Papel c={c} condiciones={catalogos!.condiciones} />

      <div className="panel no-print">
        <h3 style={{ marginTop: 0 }}>Trazabilidad</h3>
        <dl className="datos grande">
          <div><dt>Creado</dt><dd>{fechaHora(c.creado_en)} · {catalogos!.roles.find((r) => r.id === c.creado_rol)?.descripcion}</dd></div>
          {c.emitido_en && <div><dt>Emitido</dt><dd>{fechaHora(c.emitido_en)}</dd></div>}
          <div><dt>Período del libro</dt><dd>{c.periodo}</dd></div>
          <div><dt>Estado</dt><dd><Estado estado={c.estado} /></dd></div>
        </dl>
      </div>

      {nota && <ModalNota factura={c} clase={nota} onCerrar={() => setNota(null)} onListo={(n) => { setNota(null); avisar(`Se emitió ${n.etiqueta}.`); router.push(`/ventas/${n.id}`); }} />}
    </>
  );
}

function ModalNota({ factura, clase, onCerrar, onListo }: { factura: Comprobante; clase: 'credito' | 'debito'; onCerrar: () => void; onListo: (n: Comprobante) => void }) {
  const { rol, catalogos } = useApp();
  const [fechaN, setFechaN] = useState(hoy());
  const [motivo, setMotivo] = useState('');
  const [netos, setNetos] = useState<Record<number, string>>(Object.fromEntries(factura.desglose.map((d) => [d.alicuota_codigo, ''])));
  const [calc, setCalc] = useState<Calculo | null>(null);
  const [error, setError] = useState<ErrorNegocio | null>(null);
  const [enviando, setEnviando] = useState(false);
  const lineas = Object.entries(netos).map(([cod, v]) => ({ alicuota_codigo: Number(cod), neto: leerNumero(v) ?? '0' }));

  useEffect(() => {
    const t = setTimeout(() => api.calcular({ operacion: 'nota', lineas }).then(setCalc).catch(() => setCalc(null)), 250);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [JSON.stringify(lineas)]);

  async function emitir() {
    setEnviando(true); setError(null);
    try { onListo(await api.emitirNota(rol, { factura_id: factura.id, clase, fecha: fechaN, motivo, lineas })); }
    catch (e) { setError(e instanceof ErrorNegocio ? e : new ErrorNegocio('ERROR', String(e), null)); }
    finally { setEnviando(false); }
  }

  return (
    <Modal titulo={`Nota de ${clase === 'credito' ? 'crédito' : 'débito'} ${factura.letra} sobre ${factura.etiqueta}`} onCerrar={onCerrar}>
      {error && <Alerta tipo="error">{error.detalle}</Alerta>}
      <div className="grid-form">
        <Campo etiqueta="Fecha"><input className="in" type="date" value={fechaN} onChange={(e) => setFechaN(e.target.value)} /></Campo>
        <Campo etiqueta="Motivo" ancho><input className="in" value={motivo} placeholder="Ej. devolución parcial" onChange={(e) => setMotivo(e.target.value)} /></Campo>
      </div>
      <h3>Importe neto por alícuota</h3>
      <div className="filas-nota">
        {factura.desglose.map((d) => (
          <div className="fila-ali" key={d.alicuota_codigo}>
            <span>{catalogos!.alicuotas.find((a) => a.codigo === d.alicuota_codigo)?.descripcion} <small className="nota">(factura: {pesos(d.base)})</small></span>
            <input className="in num-in" inputMode="decimal" placeholder="0,00" value={netos[d.alicuota_codigo]} onChange={(e) => setNetos({ ...netos, [d.alicuota_codigo]: e.target.value })} />
            <span />
          </div>
        ))}
      </div>
      <dl className="resumen">
        <div><dt>Neto</dt><dd>{pesos(calc?.importes.neto_gravado)}</dd></div>
        <div><dt>IVA</dt><dd>{pesos(calc?.importes.iva)}</dd></div>
        <div className="gr"><dt>Total de la nota</dt><dd>{pesos(calc?.importes.total)}</dd></div>
      </dl>
      <div className="fila-b"><button className="btn primario" disabled={enviando} onClick={emitir}>Emitir nota</button><button className="btn" onClick={onCerrar}>Cancelar</button></div>
    </Modal>
  );
}
