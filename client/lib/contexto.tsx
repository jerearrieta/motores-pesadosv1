'use client';

import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { api, ErrorNegocio, type Catalogos, type Rol } from './api';

interface Toast { id: number; tipo: 'ok' | 'error'; texto: string }

interface Contexto {
  catalogos: Catalogos | null;
  errorCarga: string | null;
  empresa: string;
  setEmpresa: (e: string) => void;
  rol: Rol;
  setRol: (r: Rol) => void;
  tema: 'claro' | 'oscuro' | null;
  setTema: (t: 'claro' | 'oscuro') => void;
  puede: (accion: string) => boolean;
  avisar: (texto: string, tipo?: 'ok' | 'error') => void;
  avisarError: (e: unknown) => void;
  toasts: Toast[];
  /** Borradores sin emitir ni confirmar de la empresa elegida (contadores de las pestañas) */
  borradores: { venta: number; compra: number };
  recargarBorradores: () => void;
}

const Ctx = createContext<Contexto | null>(null);

function leer<T extends string>(k: string, def: T): T {
  try { return (localStorage.getItem(k) as T) || def; } catch { return def; }
}
function guardar(k: string, v: string) {
  try { localStorage.setItem(k, v); } catch { /* navegación privada */ }
}

export function ProveedorApp({ children }: { children: ReactNode }) {
  const [catalogos, setCatalogos] = useState<Catalogos | null>(null);
  const [errorCarga, setErrorCarga] = useState<string | null>(null);
  const [empresa, setEmpresaE] = useState('MP');
  const [rol, setRolE] = useState<Rol>('administracion');
  const [tema, setTemaE] = useState<'claro' | 'oscuro' | null>(null);
  const [toasts, setToasts] = useState<Toast[]>([]);
  const [borradores, setBorradores] = useState({ venta: 0, compra: 0 });

  useEffect(() => {
    setEmpresaE(leer('mp-empresa', 'MP'));
    setRolE(leer<Rol>('mp-rol', 'administracion'));
    const t: string = leer<string>('mp-tema', '');
    if (t === 'claro' || t === 'oscuro') setTemaE(t);
    api.catalogos().then(setCatalogos).catch((e) => setErrorCarga(e instanceof Error ? e.message : String(e)));
  }, []);

  useEffect(() => {
    if (tema) document.documentElement.dataset.theme = tema === 'oscuro' ? 'dark' : 'light';
  }, [tema]);

  const avisar = useCallback((texto: string, tipo: 'ok' | 'error' = 'ok') => {
    const id = Date.now() + Math.random();
    setToasts((t) => [...t, { id, tipo, texto }]);
    setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), tipo === 'error' ? 9000 : 4500);
  }, []);

  const recargarBorradores = useCallback(() => {
    if (!catalogos) return;
    const contar = (lista: { estado: string }[]) => lista.filter((c) => c.estado === 'borrador').length;
    Promise.all([api.comprobantes(empresa, 'venta'), api.comprobantes(empresa, 'compra')])
      .then(([v, c]) => setBorradores({ venta: contar(v), compra: contar(c) }))
      .catch(() => { /* el contador no es imprescindible */ });
  }, [catalogos, empresa]);

  const valor = useMemo<Contexto>(() => ({
    catalogos, errorCarga, empresa, rol, tema, toasts, avisar, borradores, recargarBorradores,
    setEmpresa: (e) => { setEmpresaE(e); guardar('mp-empresa', e); },
    setRol: (r) => { setRolE(r); guardar('mp-rol', r); },
    setTema: (t) => { setTemaE(t); guardar('mp-tema', t); },
    puede: (accion) => !!catalogos?.permisos[accion]?.includes(rol),
    avisarError: (e) => avisar(e instanceof ErrorNegocio ? e.detalle : e instanceof Error ? e.message : String(e), 'error'),
  }), [catalogos, errorCarga, empresa, rol, tema, toasts, avisar, borradores, recargarBorradores]);

  return <Ctx.Provider value={valor}>{children}</Ctx.Provider>;
}

export function useApp(): Contexto {
  const c = useContext(Ctx);
  if (!c) throw new Error('useApp fuera de ProveedorApp');
  return c;
}

/** Carga datos del server y los vuelve a pedir cuando cambian las dependencias. */
export function useDatos<T>(cargar: () => Promise<T>, deps: unknown[]): { datos: T | null; error: string | null; recargar: () => void; cargando: boolean } {
  const [datos, setDatos] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [cargando, setCargando] = useState(true);
  const [n, setN] = useState(0);
  useEffect(() => {
    let vivo = true;
    setCargando(true);
    cargar()
      .then((d) => { if (vivo) { setDatos(d); setError(null); } })
      .catch((e) => { if (vivo) setError(e instanceof ErrorNegocio ? e.detalle : e instanceof Error ? e.message : String(e)); })
      .finally(() => { if (vivo) setCargando(false); });
    return () => { vivo = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, n]);
  return { datos, error, cargando, recargar: () => setN((x) => x + 1) };
}
