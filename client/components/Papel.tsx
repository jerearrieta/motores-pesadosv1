'use client';

import type { Comprobante } from '@/lib/api';
import { cuit, fecha, importe, montoEnLetras } from '@/lib/formato';

/** La factura "en papel", con el diseño de la factura modelo de la empresa. Solo presentación. */
export function Papel({ c, condiciones }: { c: Comprobante; condiciones: { codigo: number; descripcion: string }[] }) {
  const e = c.empresa;
  const condEmpresa = condiciones.find((x) => x.codigo === e.condicion_iva)?.descripcion;
  const discrimina = c.letra === 'A';
  return (
    <div className="papel-wrap">
      <div className="papel modelo">
        <div className="marca">COMPROBANTE DE PRUEBA<br />SIN VALIDEZ FISCAL</div>
        <div className="m-cab">
          <div className="m-emisor">
            <div className="m-logo">LOGO<small>{e.id}</small></div>
            <strong className="m-razon">{e.razon_social}</strong>
            <span>{e.domicilio}</span>
            <span>Tel. {e.telefono}</span>
            <span>{condEmpresa}</span>
          </div>
          <div className="m-letra">
            <b>{c.letra}</b>
            <span>Cód. {String(c.tipo).padStart(2, '0')}</span>
            <strong>{c.tipo_desc.replace(/ [ABC]$/, '').toUpperCase()}</strong>
          </div>
          <div className="m-num">
            <span>Nº</span>
            <strong className="m-n">{c.numero_texto}</strong>
            <span>Fecha: <b>{fecha(c.fecha)}</b></span>
            <span>CUIT: {cuit(e.cuit)}</span>
            <span>Ingresos Brutos: {e.ingresos_brutos}</span>
            <span>Inicio de actividades: {fecha(e.inicio_actividades)}</span>
          </div>
        </div>
        <div className="m-rec">
          <div className="s4 m-sr"><span>Señores</span><br /><strong>{c.contraparte_razon}</strong></div>
          <div className="s2"><span>{c.contraparte_tipo_doc === 99 ? 'Documento' : 'CUIT'}</span><br /><b>{c.documento}</b></div>
          <div className="s4"><span>Domicilio</span><br />{c.contraparte_domicilio || '—'}</div>
          <div className="s2"><span>Condición IVA</span><br />{c.condicion_desc}</div>
        </div>
        <div className="m-cv">
          <div><span>Condición de venta: </span>{c.condicion_venta || '—'}</div>
          {c.presupuesto && <div><span>Presupuesto: </span>{c.presupuesto}</div>}
          {c.orden_compra && <div><span>Orden de compra: </span>{c.orden_compra}</div>}
          {c.remito && <div><span>Remito: </span>{c.remito}</div>}
          {c.asociado && <div><span>Comprobante asociado: </span>{c.asociado.etiqueta}</div>}
        </div>
        <table className="m-items">
          <thead><tr><th>Código</th><th className="num">Cant.</th><th>Descripción</th><th className="num">Precio lista</th><th className="num">Dto. %</th><th className="num">P. unitario</th><th className="num">IVA</th><th className="num">Importe</th></tr></thead>
          <tbody>
            {c.items.map((i) => (
              <tr key={i.orden}>
                <td>{i.codigo}</td><td className="num">{importe(i.cantidad)}</td><td className="desc">{i.descripcion}</td>
                <td className="num">{importe(i.precio_lista)}</td><td className="num">{Number(i.descuento) ? importe(i.descuento) : ''}</td>
                <td className="num">{importe(i.precio_unitario)}</td>
                <td className="num">{c.desglose.find((d) => d.alicuota_codigo === i.alicuota_codigo)?.porcentaje ?? ''} %</td>
                <td className="num">{importe(i.importe_neto)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <div className="m-espacio" />
        <div className="m-letras">{montoEnLetras(c.total)}</div>
        <div className="m-pie">
          <div>
            <p className="m-ley">{e.leyenda}</p>
            {c.motivo && <p><b>Motivo:</b> {c.motivo}</p>}
            <div className="m-cae">
              <div className="m-qr">QR<small>de ARCA</small></div>
              <div>
                <p><span>CAE: </span><b>{c.cae || 'sin CAE (todavía no se pide a ARCA)'}</b></p>
                <p><span>Vto. CAE: </span>{fecha(c.vto_cae) || '—'}</p>
                <p className="m-aviso">Comprobante de prueba: no tiene validez fiscal.</p>
              </div>
            </div>
          </div>
          <div>
            {discrimina ? (
              <>
                <table className="m-iva">
                  <thead><tr><th>Alícuota</th><th>Neto</th><th>IVA</th></tr></thead>
                  <tbody>{c.desglose.map((d) => <tr key={d.alicuota_codigo}><td className="num">{String(d.porcentaje).replace('.', ',')} %</td><td className="num">{importe(d.base)}</td><td className="num">{importe(d.iva)}</td></tr>)}</tbody>
                </table>
                <table className="m-tot"><tbody>
                  <tr><td>Neto gravado</td><td className="num">{importe(c.neto_gravado)}</td></tr>
                  <tr><td>IVA</td><td className="num">{importe(c.iva)}</td></tr>
                  <tr className="g"><td>TOTAL $</td><td className="num">{importe(c.total)}</td></tr>
                </tbody></table>
              </>
            ) : (
              <>
                <p className="m-ivainc">IVA contenido (Ley 27.743): $ {importe(c.iva)}</p>
                <table className="m-tot"><tbody><tr className="g"><td>TOTAL $</td><td className="num">{importe(c.total)}</td></tr></tbody></table>
              </>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
