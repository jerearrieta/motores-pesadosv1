'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { api } from '@/lib/api';
import { useApp, useDatos } from '@/lib/contexto';
import { fecha, periodoLargo, pesos } from '@/lib/formato';
import { Icono } from '@/components/Icono';
import { SeccionesCompra } from '@/components/Bandeja';
import { Alerta, Cabecera, Cargando, Estado, useEmpresa } from '@/components/ui';

export default function PaginaCompras() {
  const { empresa, puede } = useApp();
  const emp = useEmpresa();
  const router = useRouter();
  const [periodo, setPeriodo] = useState('');
  const [estado, setEstado] = useState('');
  const lista = useDatos(() => api.comprobantes(empresa, 'compra'), [empresa]);

  const periodos = [...new Set(lista.datos?.map((c) => c.periodo) ?? [])].sort().reverse();
  const filas = (lista.datos ?? []).filter((c) => (!periodo || c.periodo === periodo) && (!estado || c.estado === estado));

  return (
    <>
      <Cabecera icono="carro" titulo="Facturas de compra" bajada={<>Comprobantes de proveedores de {emp.razon_social}: alimentan el crédito fiscal del libro de compras.</>}>
      </Cabecera>
      <SeccionesCompra />
      <div className="filtros">
        <label className="filtro"><span>Período de IVA</span>
          <select className="in" value={periodo} onChange={(e) => setPeriodo(e.target.value)} style={{ width: 'auto' }}>
            <option value="">Todos</option>
            {periodos.map((p) => <option key={p} value={p}>{periodoLargo(p)}</option>)}
          </select>
        </label>
        <label className="filtro"><span>Estado</span>
          <select className="in" value={estado} onChange={(e) => setEstado(e.target.value)} style={{ width: 'auto' }}>
            <option value="">Todos</option><option value="borrador">Borrador</option><option value="confirmada">Confirmada</option><option value="anulada">Anulada</option>
          </select>
        </label>
        <div className="filtros-d">
          {puede('cargar_compra') && <Link className="btn primario" href="/bandeja-tesoreria/facturas-de-compra/cargar-factura-de-compra"><Icono n="mas" /> Cargar factura de compra</Link>}
        </div>
      </div>
      {lista.error && <Alerta tipo="error">{lista.error}</Alerta>}
      {!lista.datos ? <Cargando /> : (
        <div className="panel flush">
          {filas.length === 0 ? <p className="vacio">No hay comprobantes con estos filtros.</p> : (
            <div className="tabla-wrap">
              <table className="tabla">
                <thead><tr><th>Comprobante</th><th>Fecha</th><th>Período</th><th>Proveedor</th><th>Orden o categoría</th><th>Estado</th><th className="adj-c">Respaldo</th><th className="num">IVA</th><th className="num">Total</th></tr></thead>
                <tbody>
                  {filas.map((c) => (
                    <tr key={c.id} data-act onClick={() => router.push(`/bandeja-tesoreria/facturas-de-compra/${c.id}`)}>
                      <th>{c.tipo_desc}<small className="mono">{c.numero_texto}</small>{c.asociado && <small>sobre {c.asociado}</small>}</th>
                      <td className="mono nw">{fecha(c.fecha)}</td>
                      <td className="mono nw">{c.periodo}</td>
                      <td className="nom">{c.contraparte}<small className="mono">{c.documento}</small></td>
                      <td>{c.orden_compra ? <span className="mono">{c.orden_compra}</span> : c.categoria_gasto || (c.clase === 'factura' ? <span className="sin-adj">falta</span> : '—')}</td>
                      <td><Estado estado={c.estado} />{c.en_revision && <span className="pill naranja">En revisión</span>}{c.motivo_anulacion && <small>{c.motivo_anulacion}</small>}</td>
                      <td className="adj-c">{c.imagen_path ? <Icono n="clip" t={16} /> : c.cae ? <span className="sin-adj">CAE</span> : c.origen === 'arca' ? <span className="sin-adj">ARCA</span> : <span className="sin-adj">falta</span>}</td>
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
