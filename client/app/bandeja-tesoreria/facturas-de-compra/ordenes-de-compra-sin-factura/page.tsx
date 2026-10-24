'use client';

import Link from 'next/link';
import { api } from '@/lib/api';
import { useApp, useDatos } from '@/lib/contexto';
import { fecha, pesos } from '@/lib/formato';
import { RUTAS } from '@/lib/rutas';
import { SeccionesCompra } from '@/components/Bandeja';
import { Alerta, Cabecera, Cargando, Stat, useEmpresa } from '@/components/ui';

/** Órdenes de compra recibidas sin factura (deuda sin documentar), facturas sin orden ni categoría y compras en revisión de precio (US-063). */
export default function OrdenesSinFactura() {
  const { empresa } = useApp();
  const emp = useEmpresa();
  const b = useDatos(() => api.bandejaCompras(empresa), [empresa]);
  const d = b.datos;
  return (
    <>
      <Cabecera icono="carro" titulo="Facturas de compra"
        bajada={<>Comprobantes de proveedores de {emp.razon_social}: alimentan el crédito fiscal del libro de compras.</>} />
      <SeccionesCompra />
      {b.error && <Alerta tipo="error">{b.error}</Alerta>}
      {!d ? <Cargando /> : (
        <>
          <div className="stats chicas">
            <Stat color="naranja" valor={d.ordenes_sin_factura.length} titulo="Órdenes recibidas sin factura" />
            <Stat color="rojo" valor={pesos(d.deuda_sin_documentar)} titulo="Deuda sin documentar" detalle="Saldo sin IVA de esas órdenes" />
            <Stat color="violeta" valor={d.en_revision.length} titulo="En revisión de precio" />
            <Stat valor={d.facturas_sin_orden.length} titulo="Facturas sin orden ni categoría" />
          </div>
          <section className="panel flush">
            <div className="panel-h"><h2>Órdenes de compra recibidas sin factura</h2></div>
            <div className="tabla-wrap"><table className="tabla">
              <thead><tr><th>Orden de compra</th><th>Presupuesto de venta</th><th>Proveedor</th><th>Recibida</th><th className="num">Antigüedad</th>
                <th className="num">Importe</th><th className="num">Facturado</th><th className="num">Saldo</th></tr></thead>
              <tbody>
                {d.ordenes_sin_factura.map((o) => (
                  <tr key={o.id}>
                    <th className="mono">{o.numero}<small>{o.descripcion}</small></th><td className="mono">{o.presupuesto}</td><td>{o.proveedor}</td>
                    <td className="mono nw">{fecha(o.fecha_recepcion)}</td>
                    <td className="num">{o.antiguedad == null ? '—' : `${o.antiguedad} ${o.antiguedad === 1 ? 'día' : 'días'}`}</td>
                    <td className="num">{pesos(o.importe)}</td><td className="num">{pesos(o.facturado)}</td><td className="num strong">{pesos(o.saldo)}</td>
                  </tr>
                ))}
                {!d.ordenes_sin_factura.length && <tr><td colSpan={8} className="vacio">No hay órdenes recibidas sin factura.</td></tr>}
              </tbody>
            </table></div>
          </section>
          {d.en_revision.length > 0 && (
            <section className="panel flush">
              <div className="panel-h"><h2>Compras en revisión de precio</h2></div>
              <div className="tabla-wrap"><table className="tabla">
                <thead><tr><th>Comprobante</th><th>Proveedor</th><th className="num">Sin IVA</th><th className="num">Saldo de las órdenes</th><th className="num">Diferencia</th><th className="num">Tolerancia</th></tr></thead>
                <tbody>{d.en_revision.map((c) => (
                  <tr key={c.id}><th><Link href={`${RUTAS.compras}/${c.id}`}>{c.etiqueta}</Link></th><td>{c.proveedor}</td><td className="num">{pesos(c.base)}</td>
                    <td className="num">{pesos(c.saldo)}</td><td className="num strong">{pesos(c.diferencia)}</td><td className="num">{pesos(c.tolerancia)}</td></tr>
                ))}</tbody>
              </table></div>
            </section>
          )}
          {d.facturas_sin_orden.length > 0 && (
            <section className="panel flush">
              <div className="panel-h"><h2>Facturas sin orden de compra ni categoría de gasto</h2></div>
              <div className="tabla-wrap"><table className="tabla">
                <thead><tr><th>Comprobante</th><th>Proveedor</th><th>Fecha</th><th className="num">Total</th></tr></thead>
                <tbody>{d.facturas_sin_orden.map((c) => (
                  <tr key={c.id}><th><Link href={`${RUTAS.compras}/${c.id}`}>{c.etiqueta}</Link></th><td>{c.proveedor}</td>
                    <td className="mono nw">{fecha(c.fecha)}</td><td className="num">{pesos(c.total)}</td></tr>
                ))}</tbody>
              </table></div>
            </section>
          )}
        </>
      )}
    </>
  );
}
