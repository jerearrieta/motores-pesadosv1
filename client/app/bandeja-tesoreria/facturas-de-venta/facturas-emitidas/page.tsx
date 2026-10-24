'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { api } from '@/lib/api';
import { useApp, useDatos } from '@/lib/contexto';
import { fecha, periodoLargo, pesos } from '@/lib/formato';
import { Icono } from '@/components/Icono';
import { Alerta, Cabecera, Cargando, Estado, useEmpresa } from '@/components/ui';

export default function PaginaVentas() {
  const { empresa, puede } = useApp();
  const emp = useEmpresa();
  const router = useRouter();
  const [periodo, setPeriodo] = useState('');
  const [estado, setEstado] = useState('');
  const lista = useDatos(() => api.comprobantes(empresa, 'venta'), [empresa]);

  const periodos = [...new Set(lista.datos?.map((c) => c.periodo) ?? [])].sort().reverse();
  const filas = (lista.datos ?? []).filter((c) => (!periodo || c.periodo === periodo) && (!estado || c.estado === estado));

  return (
    <>
      <Cabecera icono="recibo" titulo="Facturas de venta" bajada={<>Comprobantes emitidos por {emp.razon_social}: alimentan el débito fiscal del libro de ventas.</>}>
      </Cabecera>
      <div className="filtros">
        <label className="filtro"><span>Período</span>
          <select className="in" value={periodo} onChange={(e) => setPeriodo(e.target.value)} style={{ width: 'auto' }}>
            <option value="">Todos</option>
            {periodos.map((p) => <option key={p} value={p}>{periodoLargo(p)}</option>)}
          </select>
        </label>
        <label className="filtro"><span>Estado</span>
          <select className="in" value={estado} onChange={(e) => setEstado(e.target.value)} style={{ width: 'auto' }}>
            <option value="">Todos</option><option value="borrador">Borrador</option><option value="emitido_sin_cae">Emitida sin CAE</option><option value="autorizado">Autorizada</option>
          </select>
        </label>
        <div className="filtros-d">
          {puede('emitir_venta') && <Link className="btn primario" href="/bandeja-tesoreria/facturas-de-venta/facturas-emitidas/nueva"><Icono n="mas" /> Factura sin presupuesto</Link>}
        </div>
      </div>
      {lista.error && <Alerta tipo="error">{lista.error}</Alerta>}
      {!lista.datos ? <Cargando /> : (
        <div className="panel flush">
          {filas.length === 0 ? <p className="vacio">No hay comprobantes con estos filtros.</p> : (
            <div className="tabla-wrap">
              <table className="tabla">
                <thead><tr><th>Comprobante</th><th>Fecha</th><th>Cliente</th><th>Estado</th><th className="num">Neto</th><th className="num">IVA</th><th className="num">Total</th></tr></thead>
                <tbody>
                  {filas.map((c) => (
                    <tr key={c.id} data-act onClick={() => router.push(`/bandeja-tesoreria/facturas-de-venta/facturas-emitidas/${c.id}`)}>
                      <th>{c.tipo_desc}<small className="mono">{c.numero_texto}</small>{c.asociado && <small>sobre {c.asociado}</small>}</th>
                      <td className="mono nw">{fecha(c.fecha)}</td>
                      <td className="nom">{c.contraparte}<small className="mono">{c.documento}</small></td>
                      <td><Estado estado={c.estado} /></td>
                      <td className={`num${c.clase === 'nota_credito' ? ' neg' : ''}`}>{c.clase === 'nota_credito' ? '−' : ''}{pesos(c.neto_gravado)}</td>
                      <td className={`num${c.clase === 'nota_credito' ? ' neg' : ''}`}>{c.clase === 'nota_credito' ? '−' : ''}{pesos(c.iva)}</td>
                      <td className={`num strong${c.clase === 'nota_credito' ? ' neg' : ''}`}>{c.clase === 'nota_credito' ? '−' : ''}{pesos(c.total)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </>
  );
}
