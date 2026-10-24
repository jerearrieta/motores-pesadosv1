'use client';

import { useEffect, useState } from 'react';
import { api } from '@/lib/api';
import { useApp, useDatos } from '@/lib/contexto';
import { fechaHora, periodoLargo, pesos, contar } from '@/lib/formato';
import { Icono } from '@/components/Icono';
import { Alerta, Cabecera, Cargando, useEmpresa } from '@/components/ui';

export default function PaginaCierre() {
  const { empresa, rol, puede, avisar, avisarError } = useApp();
  const emp = useEmpresa();
  const periodos = useDatos(() => api.periodos(empresa), [empresa]);
  const [periodo, setPeriodo] = useState<string | null>(null);
  const [cerrando, setCerrando] = useState(false);

  useEffect(() => {
    if (periodos.datos?.length && (!periodo || !periodos.datos.some((p) => p.periodo === periodo))) {
      const actual = new Date().toISOString().slice(0, 7);
      setPeriodo((periodos.datos.find((p) => p.estado === 'abierto' && p.periodo <= actual) ?? periodos.datos[0]).periodo);
    }
  }, [periodos.datos, periodo]);

  const pend = useDatos(() => (periodo ? api.pendientesCierre(empresa, periodo) : Promise.resolve(null)), [empresa, periodo]);
  const historial = useDatos(() => (puede('ver_historial') ? api.historial(rol, empresa) : Promise.resolve(null)), [empresa, rol]);

  async function cerrar() {
    if (!periodo || !confirm(`¿Cerrar ${periodoLargo(periodo)} de ${emp.nombre_corto}? Después no se puede emitir, cargar ni anular con fecha de ese mes.`)) return;
    setCerrando(true);
    try {
      await api.cerrarPeriodo(rol, empresa, periodo);
      avisar(`Se cerró ${periodoLargo(periodo)}.`);
      periodos.recargar(); pend.recargar(); historial.recargar();
    } catch (e) { avisarError(e); } finally { setCerrando(false); }
  }

  return (
    <>
      <Cabecera icono="calendario" titulo="Cierre e historial" bajada="Un período cerrado bloquea emitir, cargar y anular comprobantes con fecha de ese mes. Lo cierra el Contador.">
      </Cabecera>
      {periodos.error && <Alerta tipo="error">{periodos.error}</Alerta>}
      {!periodos.datos ? <Cargando /> : (
        <div className="dos-col ancha">
          <div className="panel flush">
            <div className="panel-h"><h2>Períodos de {emp.nombre_corto}</h2></div>
            <div className="tabla-wrap">
              <table className="tabla">
                <thead><tr><th>Período</th><th className="num">Saldo</th><th>Estado</th></tr></thead>
                <tbody>
                  {periodos.datos.map((p) => (
                    <tr key={p.periodo} data-act onClick={() => setPeriodo(p.periodo)} className={p.periodo === periodo ? 'sel' : ''}>
                      <th style={p.periodo === periodo ? { boxShadow: 'inset 3px 0 0 var(--accent)' } : undefined}>{periodoLargo(p.periodo)}<small>{contar(p.ventas, 'venta', 'ventas')} · {contar(p.compras, 'compra', 'compras')}</small></th>
                      <td className={`num${p.saldo < 0 ? ' favor' : ''}`}>{p.saldo < 0 ? `A favor ${pesos(-p.saldo)}` : p.saldo > 0 ? `A pagar ${pesos(p.saldo)}` : pesos(0)}</td>
                      <td>{p.estado === 'cerrado' ? <span className="pill"><Icono n="candado" t={12} /> Cerrado</span> : <span className="pill verde">Abierto</span>}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
          <div className="col-form">
            {periodo && (
              <div className="panel">
                <div className="panel-h"><h2>Antes de cerrar {periodoLargo(periodo)}</h2></div>
                {!pend.datos ? <Cargando /> : (
                  <>
                    <ul className="checklist">
                      {pend.datos.items.map((i) => (
                        <li key={i.texto} className={i.nivel}>
                          <Icono n={i.nivel === 'ok' ? 'tilde' : 'alerta'} />
                          <div>{i.texto}{i.ayuda && <small>{i.ayuda}</small>}</div>
                          <b>{i.cantidad}</b>
                        </li>
                      ))}
                    </ul>
                    {pend.datos.estado === 'cerrado' ? <Alerta tipo="info">Este período ya está cerrado.</Alerta>
                      : puede('cerrar_periodo') ? (
                        <div className="fila-b">
                          <button className="btn primario" disabled={cerrando || pend.datos.bloquea} onClick={cerrar}><Icono n="candado" /> Cerrar período</button>
                          {pend.datos.revisar > 0 && <span className="aviso-t">{pend.datos.revisar === 1 ? 'Hay 1 punto' : `Hay ${pend.datos.revisar} puntos`} para revisar (no impiden cerrar).</span>}
                        </div>
                      ) : <p className="nota">Solo el Contador cierra períodos. Cambiá el rol abajo a la izquierda para probarlo.</p>}
                  </>
                )}
              </div>
            )}
            <div className="panel">
              <div className="panel-h"><h2>Historial de cambios</h2><span className="nota">Solo altas: no se edita ni se borra.</span></div>
              {!puede('ver_historial') ? <p className="nota">Tu rol no ve el historial (lo ven Contador, Gerencia, Administrador técnico y el perfil de estudiante).</p>
                : !historial.datos ? <Cargando /> : (
                  <ul className="timeline">
                    {historial.datos.slice(0, 60).map((h) => (
                      <li key={h.n} className={h.accion.startsWith('anul') || h.accion.startsWith('borr') ? 'rojo' : h.accion.startsWith('emit') || h.accion.startsWith('confirm') ? 'verde' : h.accion.startsWith('cerr') ? 'naranja' : ''}>
                        <time>{fechaHora(h.cuando)} · {h.rol_desc}</time>
                        <p><strong>{h.accion}</strong> {h.entidad} {h.ref && <span className="mono">{h.ref.length > 30 ? '' : h.ref}</span>}{h.detalle && <> · {h.detalle}</>}</p>
                      </li>
                    ))}
                  </ul>
                )}
            </div>
          </div>
        </div>
      )}
    </>
  );
}
