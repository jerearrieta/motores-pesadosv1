'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useEffect, useState, type ReactNode } from 'react';
import { useApp } from '@/lib/contexto';
import { faltaConfiguracion } from '@/lib/supabase';
import { Icono } from './Icono';
import type { Rol } from '@/lib/api';
import { BANDEJA } from '@/lib/rutas';

// Menú lateral como el del CRM: el módulo no tiene sección propia, vive en pestañas dentro de «Bandeja Tesorería».
const SECCIONES: { titulo: string; items: { href: string; texto: string; icono: string; borradores?: boolean }[] }[] = [
  { titulo: 'Mi bandeja', items: [
    { href: BANDEJA, texto: 'Bandeja Tesorería', icono: 'banco', borradores: true },
  ] },
  { titulo: 'Comercial', items: [
    { href: '/clientes', texto: 'Clientes', icono: 'usuarios' },
  ] },
  { titulo: 'Sistema', items: [
    { href: '/proveedores', texto: 'Proveedores', icono: 'maletin' },
  ] },
];

export function Shell({ children }: { children: ReactNode }) {
  const ruta = usePathname();
  const [abierto, setAbierto] = useState(false);
  const app = useApp();
  // Sin tema elegido, la pantalla sigue al del equipo: el botón marcado tiene que coincidir con lo que se ve
  const [sistemaOscuro, setSistemaOscuro] = useState(false);
  useEffect(() => {
    const m = window.matchMedia('(prefers-color-scheme: dark)');
    setSistemaOscuro(m.matches);
    const cambio = (e: MediaQueryListEvent) => setSistemaOscuro(e.matches);
    m.addEventListener('change', cambio);
    return () => m.removeEventListener('change', cambio);
  }, []);
  const oscuro = app.tema ? app.tema === 'oscuro' : sistemaOscuro;

  if (faltaConfiguracion) {
    return (
      <main className="main config-falta">
        <div className="panel">
          <h2>Falta conectar Supabase</h2>
          <p className="nota" style={{ margin: '10px 0' }}>
            Creá <code>client/.env.local</code> (o cargá estas variables en Vercel) con los datos de Project Settings → API:
          </p>
          <pre>{'NEXT_PUBLIC_SUPABASE_URL=https://xxxx.supabase.co\nNEXT_PUBLIC_SUPABASE_ANON_KEY=eyJ...'}</pre>
        </div>
      </main>
    );
  }

  const rolDesc = app.catalogos?.roles.find((r) => r.id === app.rol)?.descripcion ?? '';

  return (
    <div className="app">
      <aside className={`side${abierto ? ' abierto' : ''}`}>
        <div className="logo"><span className="logo-o" /> Motores Pesados</div>
        <nav className="nav" aria-label="Secciones">
          {SECCIONES.map((s) => (
            <div className="nav-sec" key={s.titulo}>
              <div className="nav-sec-t" style={{ cursor: 'default' }}>{s.titulo}</div>
              {s.items.map((i) => (
                <Link key={i.href} href={i.href} onClick={() => setAbierto(false)}
                  className={`nav-item${ruta === i.href || ruta.startsWith(i.href + '/') ? ' on' : ''}`}>
                  <Icono n={i.icono} /> {i.texto}
                  {i.borradores && app.borradores.venta + app.borradores.compra > 0 && (
                    <span className="nav-n" title="Borradores de facturas de compra y de venta">{app.borradores.venta + app.borradores.compra}</span>
                  )}
                </Link>
              ))}
            </div>
          ))}
        </nav>
        <div className="side-pie">
          <div className="tema">
            <button className={!oscuro ? 'on' : ''} onClick={() => app.setTema('claro')}><Icono n="sol" t={16} /> Claro</button>
            <button className={oscuro ? 'on' : ''} onClick={() => app.setTema('oscuro')}><Icono n="luna" t={16} /> Oscuro</button>
          </div>
          <div className="usuario">
            <div className="avatar">{rolDesc.slice(0, 1) || 'U'}</div>
            <div className="usuario-d">
              <strong>Usuario de prueba</strong>
              <label className="sr" htmlFor="rol">Rol</label>
              <select id="rol" value={app.rol} onChange={(e) => app.setRol(e.target.value as Rol)}>
                {app.catalogos?.roles.map((r) => <option key={r.id} value={r.id}>{r.descripcion}</option>)}
              </select>
            </div>
          </div>
        </div>
      </aside>
      {abierto && <div className="cortina" onClick={() => setAbierto(false)} />}
      <div className="main-col">
        <div className="banner-prueba">
          <Icono n="alerta" /> <strong>AMBIENTE DE PRUEBA:</strong> los comprobantes no tienen validez fiscal y todos los datos son inventados
          <button className="burger" onClick={() => setAbierto(true)} aria-label="Abrir menú"><Icono n="menu" /></button>
        </div>
        <main className="main">
          {app.errorCarga ? (
            <div className="alerta error"><Icono n="alerta" /><div><strong>No se pudo conectar con la base de datos.</strong><p>{app.errorCarga}</p></div></div>
          ) : !app.catalogos ? (
            <p className="cargando">Cargando…</p>
          ) : children}
        </main>
      </div>
      <div className="toasts" aria-live="polite">
        {app.toasts.map((t) => (
          <div key={t.id} className={`toast ${t.tipo}`}><Icono n={t.tipo === 'ok' ? 'tilde' : 'alerta'} /> <span>{t.texto}</span></div>
        ))}
      </div>
    </div>
  );
}
