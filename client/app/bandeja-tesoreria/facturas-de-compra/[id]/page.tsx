'use client';

import Link from 'next/link';
import { useParams, useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { api, ErrorNegocio, urlImagen } from '@/lib/api';
import { useApp, useDatos } from '@/lib/contexto';
import { fecha, fechaHora, pesos } from '@/lib/formato';
import { Icono } from '@/components/Icono';
import { Alerta, Cabecera, Campo, Cargando, Estado, Modal } from '@/components/ui';

export default function DetalleCompra() {
  const { id } = useParams<{ id: string }>();
  const { rol, catalogos, puede, avisar, avisarError } = useApp();
  const router = useRouter();
  const d = useDatos(() => api.comprobante(id), [id]);
  const [url, setUrl] = useState<string | null>(null);
  const [anulando, setAnulando] = useState(false);
  const c = d.datos;

  useEffect(() => { if (c?.imagen_path) urlImagen(c.imagen_path).then(setUrl); }, [c?.imagen_path]);

  if (d.error) return <Alerta tipo="error">{d.error}</Alerta>;
  if (!c) return <Cargando />;

  async function borrar() {
    if (!confirm('¿Borrar este borrador?')) return;
    try { await api.eliminarBorrador(rol, c!.id); avisar('Se borró el borrador.'); router.push('/bandeja-tesoreria/facturas-de-compra'); } catch (e) { avisarError(e); }
  }
  async function aprobar() {
    try { await api.aprobarDiferencia(rol, c!.id); avisar('Se aprobó la diferencia de precio.'); d.recargar(); } catch (e) { avisarError(e); }
  }
  const rolDe = (r: string | null | undefined) => catalogos!.roles.find((x) => x.id === r)?.descripcion ?? r;
  const filas: [string, number][] = [['Neto gravado', c.neto_gravado], ['IVA (crédito fiscal)', c.iva], ['No gravado', c.no_gravado], ['Exento', c.exento],
    ['Percepción de IVA', c.percepcion_iva], ['Percepción de Ingresos Brutos', c.percepcion_iibb], ['Otros tributos', c.otros_tributos]];

  return (
    <>
      <Cabecera icono="carro" titulo={c.etiqueta} bajada={<>{c.contraparte_razon} · CUIT {c.documento} · <Estado estado={c.estado} /></>}>
        <Link className="btn" href="/bandeja-tesoreria/facturas-de-compra">Volver</Link>
      </Cabecera>

      {c.estado === 'borrador' && (
        <Alerta tipo="aviso">
          <strong>Es un borrador:</strong> no suma crédito fiscal hasta que se confirme.
          <div className="fila-b">
            {puede('cargar_compra') && <Link className="btn primario chico" href={`/bandeja-tesoreria/facturas-de-compra/cargar-factura-de-compra?id=${c.id}`}><Icono n="lapiz" t={14} /> Editar y confirmar</Link>}
            {puede('cargar_compra') && <button className="btn peligro chico" onClick={borrar}><Icono n="basura" t={14} /> Borrar borrador</button>}
          </div>
        </Alerta>
      )}
      {c.estado === 'anulada' && <Alerta tipo="error"><strong>Anulada</strong> el {fechaHora(c.anulado_en!)}: {c.motivo_anulacion}. No entra en el libro.</Alerta>}

      {c.revision_precio && (c.revision_precio.aprobada_en
        ? <Alerta tipo="info">Diferencia de precio de {pesos(c.revision_precio.diferencia)} contra sus órdenes de compra, aprobada por {rolDe(c.revision_precio.aprobada_rol)} el {fecha(c.revision_precio.aprobada_en)}.</Alerta>
        : <Alerta tipo="aviso"><strong>En revisión de precio.</strong> La factura sin IVA ({pesos(c.revision_precio.base)}) difiere en {pesos(c.revision_precio.diferencia)} del saldo de sus órdenes de compra
            ({pesos(c.revision_precio.saldo)}) y supera la tolerancia de {pesos(c.revision_precio.tolerancia)}. No se puede pagar hasta que la apruebe Contador o Gerencia.
            {puede('aprobar_diferencia') && <> <button className="btn chico" onClick={aprobar}>Aprobar la diferencia</button></>}</Alerta>)}
      <div className="dos-col">
        <div className="panel">
          <h3 style={{ marginTop: 0 }}>Respaldo</h3>
          {c.imagen_path ? (
            url ? (c.imagen_path.endsWith('.pdf') ? <a className="btn" href={url} target="_blank" rel="noreferrer"><Icono n="archivo" /> Abrir PDF</a>
              : <a href={url} target="_blank" rel="noreferrer"><img className="adj-img" src={url} alt="Factura del proveedor" style={{ width: '100%' }} /></a>)
              : <p className="nota">Cargando imagen…</p>
          ) : c.cae ? <p>CAE <span className="codigo">{c.cae}</span></p> : c.codigo_autorizacion ? <p>Código de autorización en ARCA <span className="codigo">{c.codigo_autorizacion}</span></p>
            : <p className="mal-t">Sin imagen ni CAE.</p>}
          <dl className="datos" style={{ marginTop: 14 }}>
            <div><dt>Fecha</dt><dd>{fecha(c.fecha)}</dd></div>
            <div><dt>Período de IVA</dt><dd>{c.periodo}</dd></div>
            <div><dt>Vence el pago</dt><dd>{fecha(c.vencimiento_pago) || '—'}</dd></div>
            <div><dt>Condición IVA</dt><dd>{c.condicion_desc}</dd></div>
            {c.ordenes.length > 0 ? <div><dt>{c.ordenes.length === 1 ? 'Orden de compra' : 'Órdenes de compra'}</dt><dd>{c.ordenes.map((o) => `${o.numero} (${pesos(o.importe)})`).join(', ')}</dd></div>
              : c.orden_compra && <div><dt>Orden de compra</dt><dd>{c.orden_compra}</dd></div>}
            {c.categoria_gasto && <div><dt>Categoría de gasto</dt><dd>{c.categoria_gasto}</dd></div>}
            {c.jurisdiccion_iibb && <div><dt>Jurisdicción de Ingresos Brutos</dt><dd>{c.jurisdiccion_iibb}</dd></div>}
            {(c.leyenda_cbu_informada || c.leyenda_sujeta_retencion) && <div><dt>Leyendas del proveedor</dt><dd>
              {[c.leyenda_cbu_informada && 'Informa el CBU', c.leyenda_sujeta_retencion && 'Sujeta a retención'].filter(Boolean).join(' · ')}</dd></div>}
            {c.origen === 'arca' && <div><dt>Origen</dt><dd>Importada desde ARCA</dd></div>}
            {c.asociado && <div><dt>Corrige a</dt><dd><Link href={`/bandeja-tesoreria/facturas-de-compra/${c.asociado.id}`}>{c.asociado.etiqueta}</Link></dd></div>}
            {c.motivo && <div><dt>Motivo</dt><dd>{c.motivo}</dd></div>}
          </dl>
        </div>
        <div className="panel">
          <h3 style={{ marginTop: 0 }}>Importes</h3>
          <table className="mini"><thead><tr><th>Alícuota</th><th className="num">Base</th><th className="num">IVA</th></tr></thead>
            <tbody>{c.desglose.length ? c.desglose.map((x) => <tr key={x.alicuota_codigo}><td>{String(x.porcentaje).replace('.', ',')} %</td><td className="num">{pesos(x.base)}</td><td className="num">{pesos(x.iva)}</td></tr>)
              : <tr><td colSpan={3} className="nota">Sin IVA discriminado ({c.tipo_desc})</td></tr>}</tbody>
          </table>
          <dl className="resumen" style={{ marginTop: 14 }}>
            {filas.filter(([, v]) => Number(v)).map(([t, v]) => <div key={t}><dt>{t}</dt><dd>{pesos(v)}</dd></div>)}
            <div className="gr"><dt>Total</dt><dd>{pesos(c.total)}</dd></div>
          </dl>
          {c.notas.length > 0 && <>
            <h3>Notas sobre esta factura</h3>
            <ul className="lista-n">{c.notas.map((n) => <li key={n.id}><Link href={`/bandeja-tesoreria/facturas-de-compra/${n.id}`}>{n.etiqueta}</Link> · {pesos(n.total)} · <Estado estado={n.estado} /></li>)}</ul>
          </>}
          <h3>Trazabilidad</h3>
          <ul className="timeline">
            <li><time>{fechaHora(c.creado_en)}</time><p>Cargada por {rolDe(c.creado_rol)}</p></li>
            {c.confirmado_en && <li className="verde"><time>{fechaHora(c.confirmado_en)}</time><p>Confirmada</p></li>}
            {c.anulado_en && <li className="rojo"><time>{fechaHora(c.anulado_en)}</time><p>Anulada: {c.motivo_anulacion}</p></li>}
          </ul>
          {c.estado === 'confirmada' && (
            <div className="fila-b">
              {puede('anular_compra') ? <button className="btn peligro" onClick={() => setAnulando(true)}>Anular</button>
                : <span className="nota">Solo el Contador puede anular una compra.</span>}
            </div>
          )}
        </div>
      </div>
      {anulando && <ModalAnular id={c.id} onCerrar={() => setAnulando(false)} onListo={() => { setAnulando(false); avisar('Compra anulada: salió del libro.'); d.recargar(); }} />}
    </>
  );
}

function ModalAnular({ id, onCerrar, onListo }: { id: string; onCerrar: () => void; onListo: () => void }) {
  const { rol } = useApp();
  const [motivo, setMotivo] = useState('');
  const [error, setError] = useState<string | null>(null);
  async function anular() {
    try { await api.anularCompra(rol, id, motivo); onListo(); } catch (e) { setError(e instanceof ErrorNegocio ? e.detalle : String(e)); }
  }
  return (
    <Modal titulo="Anular factura de compra" onCerrar={onCerrar}>
      <p className="nota" style={{ margin: '10px 0' }}>La compra no se borra: queda registrada como anulada, con el motivo, y deja de sumar crédito fiscal.</p>
      {error && <Alerta tipo="error">{error}</Alerta>}
      <Campo etiqueta="Motivo"><textarea className="in" value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Por ejemplo, cargada dos veces" /></Campo>
      <div className="fila-b"><button className="btn peligro" onClick={anular}>Anular</button><button className="btn" onClick={onCerrar}>Cancelar</button></div>
    </Modal>
  );
}
