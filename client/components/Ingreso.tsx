'use client';

import { createContext, useContext, useEffect, useState, type FormEvent, type ReactNode } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase, faltaConfiguracion, mailDeUsuario, usuarioDeMail } from '@/lib/supabase';

interface Sesion { usuario: string; salir: () => void }
const CtxSesion = createContext<Sesion>({ usuario: '', salir: () => {} });
export const useSesion = () => useContext(CtxSesion);

/** Pantalla de ingreso: con los datos del CRM (bajo NDA) solo entra el equipo, con usuario y contraseña. */
export function Ingreso({ children }: { children: ReactNode }) {
  const [sesion, setSesion] = useState<Session | null>(null);
  const [lista, setLista] = useState(false);
  const [permitido, setPermitido] = useState<boolean | null>(null);
  const [usuario, setUsuario] = useState('');
  const [clave, setClave] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);

  useEffect(() => {
    if (!supabase) { setLista(true); return; }
    supabase.auth.getSession().then(({ data }) => { setSesion(data.session); setLista(true); });
    const { data } = supabase.auth.onAuthStateChange((_e, s) => setSesion(s));
    return () => data.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (!supabase || !sesion) { setPermitido(null); return; }
    supabase.rpc('es_del_equipo').then(({ data, error: e }) => setPermitido(!e && data === true));
  }, [sesion]);

  const salir = () => { supabase?.auth.signOut(); setClave(''); };

  async function entrar(ev: FormEvent) {
    ev.preventDefault();
    if (!supabase) return;
    setError(null);
    setEnviando(true);
    const { error: e } = await supabase.auth.signInWithPassword({ email: mailDeUsuario(usuario), password: clave });
    setEnviando(false);
    if (e) setError(e.message === 'Invalid login credentials' ? 'Usuario o contraseña incorrectos.' : e.message);
  }

  if (faltaConfiguracion) return <>{children}</>;
  if (!lista) return <p className="cargando" style={{ padding: 40 }}>Cargando…</p>;

  if (sesion && permitido) {
    return <CtxSesion.Provider value={{ usuario: usuarioDeMail(sesion.user.email), salir }}>{children}</CtxSesion.Provider>;
  }

  return (
    <main className="ingreso">
      <form className="panel ingreso-caja" onSubmit={entrar}>
        <div className="logo"><span className="logo-o" /> Motores Pesados</div>
        <h2>Ingresar</h2>
        {sesion && permitido === false ? (
          <>
            <p className="nota">El usuario <strong>{usuarioDeMail(sesion.user.email)}</strong> no tiene acceso. Pedí que te agreguen a la lista del equipo.</p>
            <button type="button" className="btn" onClick={salir}>Salir</button>
          </>
        ) : sesion ? (
          <p className="nota">Verificando acceso…</p>
        ) : (
          <>
            <p className="nota">Los datos son confidenciales: entrá con tu usuario del equipo.</p>
            <label className="ingreso-campo">Usuario
              <input value={usuario} onChange={(e) => setUsuario(e.target.value)} autoComplete="username" autoCapitalize="none" required />
            </label>
            <label className="ingreso-campo">Contraseña
              <input type="password" value={clave} onChange={(e) => setClave(e.target.value)} autoComplete="current-password" required />
            </label>
            {error && <p className="ingreso-error" role="alert">{error}</p>}
            <button className="btn primario" type="submit" disabled={enviando}>{enviando ? 'Entrando…' : 'Entrar'}</button>
          </>
        )}
      </form>
    </main>
  );
}
