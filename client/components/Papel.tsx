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
            <div className="m-logo">LOGO<small>{e.nombre_corto}</small></div>
            <strong className="m-razon">{e.razon_social}</strong>
            <span>{e.domicilio}</span>
            <span>Teléfono: {e.telefono}</span>
            <span>{condEmpresa}</span>
          </div>
          <div className="m-letra">
            <b>{c.letra}</b>
            <span>Código {String(c.tipo).padStart(2, '0')}</span>
            <strong>ORIGINAL</strong>
          </div>
          <div className="m-num">
            <strong className="m-n">Nº {c.numero_texto}</strong>
            {/* banda negra del modelo de factura de la empresa: tipo de comprobante y fecha */}
            <div className="m-banda"><span>- {c.tipo_desc.toUpperCase()} -</span><span>{fecha(c.fecha)}</span></div>
            <span>Hoja 1 de 1</span>
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
          <thead><tr><th><Rotulo pantalla="Código" impreso="Cod. Art." /></th><th className="num"><Rotulo pantalla="Cantidad" impreso="Cant." /></th><th>Descripción</th><th className="num"><Rotulo pantalla="Precio de lista" impreso="Prec.Lista" /></th><th className="num"><Rotulo pantalla="Descuento %" impreso="Dto %" /></th><th className="num">Precio unitario</th><th className="num">IVA</th><th className="num">Importe</th></tr></thead>
          <tbody>
            {c.items.map((i, n) => {
              // Factura B: precios con el IVA incluido (no discrimina IVA)
              const b = c.lineas_iva_incluido?.[n];
              return (
              <tr key={i.orden}>
                <td>{i.codigo}</td><td className="num">{importe(i.cantidad)}</td><td className="desc">{i.descripcion}</td>
                <td className="num">{importe(b ? b.lista : i.precio_lista)}</td><td className="num">{Number(i.descuento) ? importe(i.descuento) : ''}</td>
                <td className="num">{importe(b ? b.unitario : i.precio_unitario)}</td>
                <td className="num">{String(c.desglose.find((d) => d.alicuota_codigo === i.alicuota_codigo)?.porcentaje ?? '').replace('.', ',')} %</td>
                <td className="num">{importe(b ? b.total : i.importe_neto)}</td>
              </tr>
              );
            })}
          </tbody>
        </table>
        <div className="m-espacio" />
        <div className="m-letras">{montoEnLetras(c.total)}</div>
        <div className="m-pie">
          <div>
            <p className="m-ley">{e.leyenda}</p>
            {c.motivo && <p><b>Motivo:</b> {c.motivo}</p>}
            {c.origen_moneda === 'USD' && c.origen_cotizacion && <p>Presupuesto en dólares facturado en pesos a una cotización de $ {importe(c.origen_cotizacion)} por dólar.</p>}
            {c.moneda === 'USD' && <p>Factura en dólares estadounidenses, cotización $ {importe(c.cotizacion)} por dólar.</p>}
            <div className="m-cae">
              <div className="m-qr">QR<small>de ARCA</small></div>
              <div>
                <p><span>CAE: </span><b>{c.cae || 'sin CAE (todavía no se pide a ARCA)'}</b></p>
                <p><span>Vencimiento del CAE: </span>{fecha(c.vto_cae) || '—'}</p>
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
                  <tr className="g"><td>TOTAL {c.moneda === 'USD' ? 'US$' : '$'}</td><td className="num">{importe(c.total)}</td></tr>
                </tbody></table>
              </>
            ) : (
              <>
                {c.contraparte_condicion_iva === 5 && <p className="m-ivainc"><b>A CONSUMIDOR FINAL</b></p>}
                <p className="m-ivainc">Régimen de Transparencia Fiscal al Consumidor (Ley 27.743): IVA contenido $ {importe(c.iva)} · Otros impuestos nacionales indirectos $ 0,00.</p>
                <table className="m-tot"><tbody><tr className="g"><td>TOTAL {c.moneda === 'USD' ? 'US$' : '$'}</td><td className="num">{importe(c.total)}</td></tr></tbody></table>
              </>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

/** En pantalla, palabras completas; en el comprobante impreso, los rótulos del modelo de factura de la empresa. */
function Rotulo({ pantalla, impreso }: { pantalla: string; impreso: string }) {
  return <><span className="solo-pantalla">{pantalla}</span><span className="solo-impresion">{impreso}</span></>;
}
