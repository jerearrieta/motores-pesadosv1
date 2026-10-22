'use client';

import { useState } from 'react';
import { api, ErrorNegocio, type Contraparte } from '@/lib/api';
import { useApp, useDatos } from '@/lib/contexto';
import { Icono } from './Icono';
import { Alerta, Cabecera, Campo, Cargando, Modal, SinPermiso } from './ui';

/** Clientes o proveedores con sus datos fiscales (la misma tabla en la base) */
export function Contrapartes({ tipo }: { tipo: 'cliente' | 'proveedor' }) {
  const { puede } = useApp();
  const lista = useDatos(() => api.contrapartes(tipo), [tipo]);
  const [editando, setEditando] = useState<Contraparte | 'nuevo' | null>(null);
  const [q, setQ] = useState('');
  const filas = (lista.datos ?? []).filter((c) => !q || `${c.nombre} ${c.razon_social} ${c.numero_doc}`.toLowerCase().includes(q.toLowerCase()));
  const esCliente = tipo === 'cliente';

  return (
    <>
      <Cabecera icono={esCliente ? 'usuarios' : 'maletin'} titulo={esCliente ? 'Clientes' : 'Proveedores'}
        bajada={esCliente ? 'Para emitir una factura el cliente necesita documento, razón social y condición frente al IVA: de eso sale la letra (A o B).'
          : 'Para cargar una factura de compra el proveedor necesita CUIT válido y condición frente al IVA.'}>
        {puede('datos_fiscales') && <button className="btn primario" onClick={() => setEditando('nuevo')}><Icono n="mas" /> {esCliente ? 'Nuevo cliente' : 'Nuevo proveedor'}</button>}
      </Cabecera>
      {!puede('datos_fiscales') && <SinPermiso accion="datos_fiscales" />}
      <div className="filtros">
        <div className="buscar"><Icono n="buscar" /><input placeholder="Buscar por nombre o CUIT" value={q} onChange={(e) => setQ(e.target.value)} /></div>
        <span className="cuenta">{filas.length} {esCliente ? 'clientes' : 'proveedores'}</span>
      </div>
      {lista.error && <Alerta tipo="error">{lista.error}</Alerta>}
      {!lista.datos ? <Cargando /> : (
        <div className="grilla-cards">
          {filas.map((c) => (
            <div key={c.id} className={`card-cli${c.completo ? '' : ' falta'}`}>
              <div className="cc-h">
                <div className={`avatar${c.completo ? '' : ' g'}`}>{c.nombre.slice(0, 1)}</div>
                <div><strong>{c.nombre}</strong>{c.codigo && <span className="mono">Código {c.codigo}</span>}</div>
              </div>
              <div className="cc-p">
                {c.completo ? <span className="pill verde"><Icono n="tilde" t={12} /> Datos fiscales completos</span> : <span className="pill rojo">Faltan datos fiscales</span>}
                {c.condicion_desc && <span className="pill">{c.condicion_desc}</span>}
              </div>
              <div className="cc-d">
                {c.razon_social && <div>{c.razon_social}</div>}
                {c.numero_doc && <div className="mono">{c.documento}</div>}
                {[c.domicilio, c.localidad, c.provincia].filter(Boolean).join(', ')}
              </div>
              {c.faltantes.length > 0 && <ul className="faltan">{c.faltantes.map((x) => <li key={x} className="b">{x}</li>)}</ul>}
              {puede('datos_fiscales') && <button className="btn chico" onClick={() => setEditando(c)}><Icono n="lapiz" t={14} /> {c.completo ? 'Editar' : 'Completar datos'}</button>}
            </div>
          ))}
        </div>
      )}
      {editando && <FormContraparte tipo={tipo} c={editando === 'nuevo' ? null : editando} onCerrar={() => setEditando(null)} onListo={() => { setEditando(null); lista.recargar(); }} />}
    </>
  );
}

function FormContraparte({ tipo, c, onCerrar, onListo }: { tipo: 'cliente' | 'proveedor'; c: Contraparte | null; onCerrar: () => void; onListo: () => void }) {
  const { rol, catalogos, avisar } = useApp();
  const [f, setF] = useState({
    nombre: c?.nombre ?? '', codigo: c?.codigo ?? '', tipo_doc: String(c?.tipo_doc ?? 80), numero_doc: c?.numero_doc ?? '', razon_social: c?.razon_social ?? c?.nombre ?? '',
    condicion_iva: String(c?.condicion_iva ?? ''), domicilio: c?.domicilio ?? '', localidad: c?.localidad ?? '', provincia: c?.provincia ?? '',
    telefono: c?.telefono ?? '', email: c?.email ?? '', ingresos_brutos: c?.ingresos_brutos ?? '',
  });
  const [error, setError] = useState<ErrorNegocio | null>(null);
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });
  const err = (k: string) => (error?.campo === k ? error.detalle : null);

  async function guardar() {
    setError(null);
    try {
      await api.guardarContraparte(rol, { id: c?.id, tipo, ...f });
      avisar('Datos guardados.');
      onListo();
    } catch (e) { setError(e instanceof ErrorNegocio ? e : new ErrorNegocio('ERROR', String(e), null)); }
  }

  const tiposDoc = tipo === 'proveedor' ? catalogos!.tipos_documento.filter((t) => t.codigo === 80) : catalogos!.tipos_documento;
  return (
    <Modal titulo={c ? `Datos fiscales de ${c.nombre}` : tipo === 'cliente' ? 'Nuevo cliente' : 'Nuevo proveedor'} onCerrar={onCerrar}>
      {error && !error.campo && <Alerta tipo="error">{error.detalle}</Alerta>}
      <div className="grid-form">
        <Campo etiqueta="Razón social" ancho error={err('razon_social')}><input className="in" value={f.razon_social} onChange={set('razon_social')} /></Campo>
        <Campo etiqueta="Nombre en el CRM" ayuda="Si queda vacío, se usa la razón social"><input className="in" value={f.nombre} onChange={set('nombre')} /></Campo>
        <Campo etiqueta="Código"><input className="in" value={f.codigo} onChange={set('codigo')} /></Campo>
        <Campo etiqueta="Tipo de documento" error={err('tipo_doc')}>
          <select className="in" value={f.tipo_doc} onChange={set('tipo_doc')}>{tiposDoc.map((t) => <option key={t.codigo} value={t.codigo}>{t.descripcion}</option>)}</select>
        </Campo>
        {f.tipo_doc !== '99' && <Campo etiqueta="Número" error={err('numero_doc')} ayuda="Sin guiones. Usá CUIT inventados, ej. 30-99999992-8">
          <input className="in mono" value={f.numero_doc} onChange={set('numero_doc')} /></Campo>}
        <Campo etiqueta="Condición frente al IVA" ancho error={err('condicion_iva')}>
          <select className="in" value={f.condicion_iva} onChange={set('condicion_iva')}>
            <option value="">Elegí…</option>
            {catalogos!.condiciones.map((x) => <option key={x.codigo} value={x.codigo}>{x.descripcion}{tipo === 'cliente' && x.letra_venta ? ` (Factura ${x.letra_venta})` : ''}</option>)}
          </select>
        </Campo>
        <Campo etiqueta="Domicilio" ancho><input className="in" value={f.domicilio} onChange={set('domicilio')} /></Campo>
        <Campo etiqueta="Localidad"><input className="in" value={f.localidad} onChange={set('localidad')} /></Campo>
        <Campo etiqueta="Provincia"><input className="in" value={f.provincia} onChange={set('provincia')} /></Campo>
        <Campo etiqueta="Teléfono"><input className="in" value={f.telefono} onChange={set('telefono')} /></Campo>
        <Campo etiqueta="Ingresos Brutos"><input className="in" value={f.ingresos_brutos} onChange={set('ingresos_brutos')} /></Campo>
      </div>
      <div className="fila-b"><button className="btn primario" onClick={guardar}>Guardar</button><button className="btn" onClick={onCerrar}>Cancelar</button></div>
    </Modal>
  );
}
