'use client';

import { useEffect, type ReactNode } from 'react';
import { useApp } from '@/lib/contexto';
import { ESTADOS, cuit } from '@/lib/formato';
import { Icono } from './Icono';

export function Cabecera({ icono, titulo, bajada, children }: { icono: string; titulo: string; bajada?: ReactNode; children?: ReactNode }) {
  return (
    <div className="cab">
      <div className="cab-t">
        <h1><Icono n={icono} t={30} /> {titulo}</h1>
        {bajada && <p>{bajada}</p>}
      </div>
      <div className="cab-d">{children}</div>
    </div>
  );
}

/** MP / RMP: nunca se mezclan en el libro ni en la posición */
export function SelectorEmpresa() {
  const { catalogos, empresa, setEmpresa } = useApp();
  return (
    <div className="sel-empresa" role="group" aria-label="Empresa">
      {catalogos?.empresas.map((e) => (
        <button key={e.id} className={empresa === e.id ? 'on' : ''} onClick={() => setEmpresa(e.id)} aria-pressed={empresa === e.id}>
          <span className={`punto ${e.id.toLowerCase()}`} /> {e.nombre_corto}
        </button>
      ))}
    </div>
  );
}

export function useEmpresa() {
  const { catalogos, empresa } = useApp();
  const e = catalogos?.empresas.find((x) => x.id === empresa) ?? catalogos?.empresas[0];
  return { ...e!, cuitTexto: cuit(e?.cuit) };
}

export function Estado({ estado }: { estado: string }) {
  const e = ESTADOS[estado] ?? { texto: estado, color: '' };
  return <span className={`pill estado ${e.color}`}>{e.texto}</span>;
}

export function Stat({ color, valor, titulo, detalle }: { color?: string; valor: ReactNode; titulo: string; detalle?: ReactNode }) {
  return (
    <div className={`stat ${color ?? ''}`}>
      <b>{valor}</b>
      <span>{titulo}</span>
      {detalle && <small>{detalle}</small>}
    </div>
  );
}

export function Modal({ titulo, onCerrar, children, ancho }: { titulo: string; onCerrar: () => void; children: ReactNode; ancho?: boolean }) {
  useEffect(() => {
    const f = (e: KeyboardEvent) => { if (e.key === 'Escape') onCerrar(); };
    document.addEventListener('keydown', f);
    return () => document.removeEventListener('keydown', f);
  }, [onCerrar]);
  return (
    <div className="overlay" onMouseDown={(e) => { if (e.target === e.currentTarget) onCerrar(); }}>
      <div className={`modal${ancho ? ' ancho' : ''}`} role="dialog" aria-modal="true" aria-label={titulo}>
        <div className="modal-h">
          <h2>{titulo}</h2>
          <button className="btn ghost chico" onClick={onCerrar} aria-label="Cerrar"><Icono n="cruz" /></button>
        </div>
        <div className="modal-c">{children}</div>
      </div>
    </div>
  );
}

export function Campo({ etiqueta, ayuda, error, children, ancho }: { etiqueta: string; ayuda?: ReactNode; error?: string | null; children: ReactNode; ancho?: boolean }) {
  return (
    <div className={`campo${ancho ? ' c2' : ''}`}>
      <label>{etiqueta}</label>
      {children}
      {error ? <span className="campo-msg">{error}</span> : ayuda ? <span className="ayuda">{ayuda}</span> : null}
    </div>
  );
}

export function Alerta({ tipo, children }: { tipo: 'error' | 'aviso' | 'info'; children: ReactNode }) {
  return <div className={`alerta ${tipo}`}><Icono n={tipo === 'info' ? 'info' : 'alerta'} /><div>{children}</div></div>;
}

/** Aviso de que el rol elegido no puede hacer algo */
export function SinPermiso({ accion }: { accion: string }) {
  const { catalogos, rol } = useApp();
  const roles = catalogos?.permisos[accion]?.map((r) => catalogos.roles.find((x) => x.id === r)?.descripcion).join(', ');
  const actual = catalogos?.roles.find((r) => r.id === rol)?.descripcion;
  return <div className="rol-aviso"><Icono n="info" /> Con el rol {actual} esto es solo lectura. Lo pueden hacer: {roles}. Cambiá el rol abajo a la izquierda.</div>;
}

export function Cargando() {
  return <p className="cargando">Cargando…</p>;
}
