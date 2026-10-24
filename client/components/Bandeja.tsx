'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useEffect, useRef, useState, type KeyboardEvent, type ReactNode } from 'react';
import { api } from '@/lib/api';
import { useApp, useDatos } from '@/lib/contexto';
import { BANDEJA, PESTANAS, PESTANAS_CRM, ubicar } from '@/lib/rutas';
import { SelectorEmpresa } from './ui';
import { Icono } from './Icono';

/** Flechas, Inicio y Fin mueven el foco entre las pestañas habilitadas de la fila (Enter abre la pestaña). */
function moverFoco(e: KeyboardEvent<HTMLElement>) {
  const pestanas = Array.from(e.currentTarget.querySelectorAll<HTMLElement>('[role="tab"]:not([aria-disabled="true"])'));
  const i = pestanas.indexOf(document.activeElement as HTMLElement);
  let j = -1;
  if (e.key === 'ArrowRight') j = (i + 1) % pestanas.length;
  else if (e.key === 'ArrowLeft') j = (i - 1 + pestanas.length) % pestanas.length;
  else if (e.key === 'Home') j = 0;
  else if (e.key === 'End') j = pestanas.length - 1;
  if (j < 0) return;
  e.preventDefault();
  pestanas[j].focus();
}

/**
 * Fila de pestañas de «Bandeja Tesorería»: las diez del CRM apagadas (solo marcan el lugar), una línea fina
 * y las tres del módulo. Si no entra, se desplaza hacia los costados y la pestaña activa queda a la vista.
 */
function FilaPestanas({ activa }: { activa: string }) {
  const { borradores } = useApp();
  const fila = useRef<HTMLDivElement>(null);
  const [mas, setMas] = useState({ izquierda: false, derecha: false });

  function medir() {
    const f = fila.current;
    if (!f) return;
    setMas({ izquierda: f.scrollLeft > 2, derecha: f.scrollLeft + f.clientWidth < f.scrollWidth - 2 });
  }

  // La pestaña activa queda centrada; se vuelve a centrar si cambia el ancho de las pestañas (contadores, fuentes, ventana)
  useEffect(() => {
    const f = fila.current;
    if (!f) return;
    const centrar = () => {
      const t = f.querySelector<HTMLElement>('[aria-selected="true"]');
      if (t) f.scrollLeft = t.offsetLeft - f.offsetLeft - (f.clientWidth - t.offsetWidth) / 2;
      medir();
    };
    centrar();
    document.fonts?.ready.then(centrar);
    window.addEventListener('resize', centrar);
    return () => window.removeEventListener('resize', centrar);
  }, [activa, borradores.venta, borradores.compra]);

  const correr = (sentido: number) => fila.current?.scrollBy({ left: sentido * fila.current.clientWidth * 0.7, behavior: 'smooth' });

  return (
    <div className={`bandeja-pestanas${mas.izquierda ? ' mas-izquierda' : ''}${mas.derecha ? ' mas-derecha' : ''}`}>
      {mas.izquierda && <button className="bandeja-correr izquierda" onClick={() => correr(-1)} aria-label="Ver las pestañas de la izquierda" tabIndex={-1}><Icono n="flechaL" t={16} /></button>}
      <div className="bandeja-fila" ref={fila} onScroll={medir} role="tablist" aria-label="Pestañas de Bandeja Tesorería" onKeyDown={moverFoco}>
        {PESTANAS_CRM.map((p) => (
          <span key={p} role="tab" aria-selected={false} aria-disabled="true" className="bandeja-tab apagada"
            title="Pestaña del CRM: en este producto solo marca el lugar">{p}</span>
        ))}
        <span className="bandeja-separador" aria-hidden="true" />
        {PESTANAS.map((p) => {
          const n = p.contador ? borradores[p.contador] : 0;
          const on = p.id === activa;
          return (
            <Link key={p.id} href={`${BANDEJA}/${p.id}`} role="tab" id={`pestana-${p.id}`} aria-selected={on} tabIndex={on ? 0 : -1}
              aria-controls="bandeja-panel" className={`bandeja-tab${on ? ' on' : ''}`}>
              <Icono n={p.icono} t={16} /> {p.texto}
              {n > 0 && <b title={`${n} ${n === 1 ? 'borrador' : 'borradores'}`}>{n}</b>}
            </Link>
          );
        })}
      </div>
      {mas.derecha && <button className="bandeja-correr derecha" onClick={() => correr(1)} aria-label="Ver las pestañas de la derecha" tabIndex={-1}><Icono n="flechaR" t={16} /></button>}
    </div>
  );
}

export function Bandeja({ children }: { children: ReactNode }) {
  const ruta = usePathname();
  const { rol, recargarBorradores } = useApp();
  const { pestana, subpestana } = ubicar(ruta);

  // Los contadores de borradores se actualizan al cambiar de pantalla (después de guardar o emitir)
  useEffect(() => { recargarBorradores(); }, [ruta, recargarBorradores]);

  return (
    <div className="bandeja">
      <div className="cab bandeja-cab">
        <div className="cab-t"><h1><Icono n="banco" t={30} /> Bandeja de Tesorería</h1></div>
        <div className="cab-d"><SelectorEmpresa /></div>
      </div>
      {rol === 'lectura' && (
        <div className="rol-aviso"><Icono n="info" /> Perfil de estudiante (solo lectura): podés mirar todo y exportar; guardar, emitir, importar, aprobar y cerrar el período quedan deshabilitados.</div>
      )}
      <FilaPestanas activa={pestana?.id ?? ''} />
      {pestana?.sub && (
        <div className="bandeja-sub" role="tablist" aria-label={`Subpestañas de ${pestana.texto}`} onKeyDown={moverFoco}>
          {pestana.sub.map((s) => {
            const on = s.id === subpestana?.id;
            return (
              <Link key={s.id} href={`${BANDEJA}/${pestana.id}/${s.id}`} role="tab" aria-selected={on} tabIndex={on ? 0 : -1}
                aria-controls="bandeja-panel" className={`bandeja-subtab${on ? ' on' : ''}`}>{s.texto}</Link>
            );
          })}
        </div>
      )}
      <div id="bandeja-panel" role="tabpanel" aria-labelledby={pestana ? `pestana-${pestana.id}` : undefined}>{children}</div>
    </div>
  );
}

/** Secciones dentro de la pestaña «Facturas de compra» (no son subpestañas de la bandeja). */
export function SeccionesCompra() {
  const ruta = usePathname();
  const { borradores, empresa } = useApp();
  const base = `${BANDEJA}/facturas-de-compra`;
  const bandeja = useDatos(() => api.bandejaCompras(empresa), [empresa, ruta]);
  const secciones = [
    { href: base, texto: 'Facturas cargadas', n: borradores.compra },
    { href: `${base}/cargar-factura-de-compra`, texto: 'Cargar factura de compra', n: 0 },
    { href: `${base}/ordenes-de-compra-sin-factura`, texto: 'Órdenes de compra sin factura', n: bandeja.datos?.ordenes_sin_factura.length ?? 0 },
    { href: `${base}/importar-desde-arca`, texto: 'Importar desde ARCA', n: 0 },
  ];
  return (
    <nav className="tabs grande secciones" aria-label="Secciones de Facturas de compra">
      {secciones.map((s) => (
        <Link key={s.href} href={s.href} className={ruta === s.href ? 'on' : ''} aria-current={ruta === s.href ? 'page' : undefined}>
          {s.texto}{s.n > 0 && <b>{s.n}</b>}
        </Link>
      ))}
    </nav>
  );
}
