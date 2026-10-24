'use client';

import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense, useEffect, useMemo, useState } from 'react';
import { api, ErrorNegocio, subirImagen, urlImagen, type Calculo, type ComprobanteArca } from '@/lib/api';
import { PRECARGA_ARCA } from '@/components/ConciliacionArca';
import { useApp, useDatos } from '@/lib/contexto';
import { fecha, hoy, leerNumero, pesos } from '@/lib/formato';
import { Icono } from '@/components/Icono';
import { SeccionesCompra } from '@/components/Bandeja';
import { Alerta, Cabecera, Campo, Cargando, SinPermiso, useEmpresa } from '@/components/ui';

interface FilaAli { alicuota_codigo: number; base: string }
const EXTRAS = [['no_gravado', 'No gravado'], ['exento', 'Exento'], ['percepcion_iva', 'Percepción de IVA'], ['percepcion_iibb', 'Percepción de Ingresos Brutos'], ['otros_tributos', 'Otros tributos']] as const;
type Extra = (typeof EXTRAS)[number][0];

export default function Pagina() {
  return <Suspense fallback={<Cargando />}><FormCompra /></Suspense>;
}

function FormCompra() {
  const { empresa, rol, catalogos, puede, avisar } = useApp();
  const emp = useEmpresa();
  const router = useRouter();
  const idBorrador = useSearchParams().get('id');
  const proveedores = useDatos(() => api.contrapartes('proveedor'), []);
  const comprasConfirmadas = useDatos(() => api.comprobantes(empresa, 'compra'), [empresa]);
  const tiposCompra = catalogos!.tipos.filter((t) => t.compra);

  const [f, setF] = useState({ contraparte_id: '', tipo: 1, punto_venta: '', numero: '', fecha: hoy(), periodo: hoy().slice(0, 7), vencimiento_pago: '', cae: '',
    orden_compra: '', presupuesto: '', asociado_id: '', motivo: '', observaciones: '' });
  const [periodoManual, setPeriodoManual] = useState(false);
  const [arca, setArca] = useState<ComprobanteArca | null>(null);   // datos que trajo «Cargar a mano» desde la conciliación con ARCA
  const [desglose, setDesglose] = useState<FilaAli[]>([{ alicuota_codigo: 5, base: '' }]);
  const [extras, setExtras] = useState<Record<Extra, string>>({ no_gravado: '', exento: '', percepcion_iva: '', percepcion_iibb: '', otros_tributos: '' });
  const [imagen, setImagen] = useState<{ path: string; nombre: string; url: string | null; pdf: boolean } | null>(null);
  const [subiendo, setSubiendo] = useState(false);
  const [calc, setCalc] = useState<Calculo | null>(null);
  const [errorCalc, setErrorCalc] = useState<string | null>(null);
  const [error, setError] = useState<ErrorNegocio | null>(null);
  const [enviando, setEnviando] = useState(false);
  // Orden de compra o categoría de gasto (US-061 y US-062), leyendas del proveedor (US-068) y jurisdicción de Ingresos Brutos (US-112)
  const [ordenesSel, setOrdenesSel] = useState<string[]>([]);
  const [categoria, setCategoria] = useState('');
  const [leyendas, setLeyendas] = useState({ cbu_informada: false, sujeta_retencion: false });
  const [jurisdiccion, setJurisdiccion] = useState('');
  const catCompras = useDatos(() => api.catalogosCompras(), []);
  const ordenes = useDatos(() => (f.contraparte_id ? api.ordenesDisponibles(empresa, f.contraparte_id, idBorrador) : Promise.resolve([])), [empresa, f.contraparte_id, idBorrador]);

  const tipo = tiposCompra.find((t) => t.codigo === f.tipo)!;

  useEffect(() => {
    if (!idBorrador) return;
    api.comprobante(idBorrador).then(async (c) => {
      setF({ contraparte_id: c.contraparte_id, tipo: c.tipo, punto_venta: String(c.punto_venta), numero: String(c.numero ?? ''), fecha: c.fecha, periodo: c.periodo,
        vencimiento_pago: c.vencimiento_pago ?? '', cae: c.cae, orden_compra: c.orden_compra, presupuesto: c.presupuesto, asociado_id: c.asociado_id ?? '',
        motivo: c.motivo, observaciones: c.observaciones });
      setPeriodoManual(c.periodo !== c.fecha.slice(0, 7));
      setDesglose(c.desglose.length ? c.desglose.map((d) => ({ alicuota_codigo: d.alicuota_codigo, base: String(d.base) })) : [{ alicuota_codigo: 5, base: '' }]);
      setExtras({ no_gravado: Number(c.no_gravado) ? String(c.no_gravado) : '', exento: Number(c.exento) ? String(c.exento) : '', percepcion_iva: Number(c.percepcion_iva) ? String(c.percepcion_iva) : '',
        percepcion_iibb: Number(c.percepcion_iibb) ? String(c.percepcion_iibb) : '', otros_tributos: Number(c.otros_tributos) ? String(c.otros_tributos) : '' });
      setOrdenesSel(c.ordenes.map((o) => o.id));
      setCategoria(c.categoria_gasto);
      setLeyendas({ cbu_informada: c.leyenda_cbu_informada, sujeta_retencion: c.leyenda_sujeta_retencion });
      setJurisdiccion(c.jurisdiccion_iibb);
      if (c.imagen_path) setImagen({ path: c.imagen_path, nombre: c.imagen_nombre ?? c.imagen_path, url: await urlImagen(c.imagen_path), pdf: c.imagen_path.endsWith('.pdf') });
    });
  }, [idBorrador]);

  // «Cargar a mano» desde la conciliación con ARCA: precarga lo que trae el archivo (el desglose se completa a mano)
  const desdeArca = useSearchParams().get('desde_arca');
  useEffect(() => {
    if (idBorrador || !desdeArca || !proveedores.datos) return;
    let a: ComprobanteArca | null = null;
    try { a = JSON.parse(sessionStorage.getItem(PRECARGA_ARCA) ?? 'null'); } catch { a = null; }
    if (!a) return;
    const arca = a;
    setArca(arca);
    const prov = proveedores.datos.find((p) => p.numero_doc === arca.cuit);
    setF((x) => ({ ...x, tipo: arca.tipo, punto_venta: String(arca.punto_venta), numero: String(arca.numero), fecha: arca.fecha, periodo: arca.fecha.slice(0, 7),
      contraparte_id: prov?.id ?? x.contraparte_id, cae: /^\d{14}$/.test(arca.cae) ? arca.cae : '',
      observaciones: `Cargada a mano desde la conciliación con ARCA (total según ARCA: ${pesos(arca.total)}; código de autorización ${arca.cae || 'sin informar'}).` }));
  }, [idBorrador, desdeArca, proveedores.datos]);

  const datosCalculo = useMemo(() => ({
    tipo: f.tipo,
    desglose: tipo.discrimina_iva ? desglose.map((d) => ({ alicuota_codigo: d.alicuota_codigo, base: leerNumero(d.base) ?? (d.base || '0') })) : [],
    ...Object.fromEntries(EXTRAS.map(([k]) => [k, leerNumero(extras[k]) ?? (extras[k] || '0')])),
  }), [f.tipo, tipo.discrimina_iva, desglose, extras]);

  useEffect(() => {
    const t = setTimeout(() => {
      api.calcular({ operacion: 'compra', ...datosCalculo })
        .then((r) => { setCalc(r); setErrorCalc(null); })
        .catch((e) => { setCalc(null); setErrorCalc(e instanceof ErrorNegocio ? e.detalle : String(e)); });
    }, 300);
    return () => clearTimeout(t);
  }, [datosCalculo]);

  if (!puede('cargar_compra')) return <><Cabecera icono="carro" titulo="Cargar factura de compra" /><SeccionesCompra /><SinPermiso accion="cargar_compra" /></>;

  const proveedor = proveedores.datos?.find((p) => p.id === f.contraparte_id);
  const facturasProveedor = (comprasConfirmadas.datos ?? []).filter((c) => c.estado === 'confirmada' && c.clase === 'factura' && c.documento === proveedor?.documento);
  const campoError = (k: string) => (error?.campo === k ? error.detalle : null);

  async function elegirArchivo(archivo: File | undefined) {
    if (!archivo) return;
    setSubiendo(true);
    try {
      const path = await subirImagen(empresa, archivo);
      setImagen({ path, nombre: archivo.name, url: archivo.type.startsWith('image/') ? URL.createObjectURL(archivo) : null, pdf: archivo.type === 'application/pdf' });
    } catch (e) { setError(e instanceof ErrorNegocio ? e : new ErrorNegocio('ADJUNTO', String(e), 'imagen')); }
    finally { setSubiendo(false); }
  }

  async function guardar(confirmar: boolean) {
    setEnviando(true); setError(null);
    try {
      const c = await api.guardarCompra(rol, {
        id: idBorrador, empresa_id: empresa, ...f, periodo: periodoManual ? f.periodo : f.fecha.slice(0, 7), ...datosCalculo,
        codigo_autorizacion: arca?.cae ?? '',   // el código de autorización de ARCA sirve de respaldo, como al importar
        imagen_path: imagen?.path ?? null, imagen_nombre: imagen?.nombre ?? null,
        ordenes_compra: tipo.clase === 'factura' ? ordenesSel : [], categoria: tipo.clase === 'factura' ? categoria : '', leyendas, jurisdiccion_iibb: jurisdiccion,
      }, confirmar);
      avisar(confirmar ? `Se confirmó ${c.etiqueta} por ${pesos(c.total)}.` : 'Se guardó el borrador.');
      if (c.revision_precio) avisar(`Quedó en revisión de precio: la factura sin IVA difiere en ${pesos(c.revision_precio.diferencia)} del saldo de sus órdenes de compra (tolerancia ${pesos(c.revision_precio.tolerancia)}). La aprueba Contador o Gerencia.`, 'error');
      router.push(`/bandeja-tesoreria/facturas-de-compra/${c.id}`);
    } catch (e) {
      setError(e instanceof ErrorNegocio ? e : new ErrorNegocio('ERROR', String(e), null));
      window.scrollTo({ top: 0, behavior: 'smooth' });
    } finally { setEnviando(false); }
  }

  return (
    <>
      <Cabecera icono="carro" titulo={idBorrador ? 'Editar borrador de compra' : 'Cargar factura de compra'}
        bajada={<>{emp.razon_social} · se carga lo que dice el papel del proveedor; el IVA y el total los calcula el sistema.</>}>
        <Link className="btn" href="/bandeja-tesoreria/facturas-de-compra">Volver</Link>
      </Cabecera>
      <SeccionesCompra />
      {arca && !idBorrador && (
        <Alerta tipo="aviso"><strong>Datos traídos de ARCA.</strong> El archivo dice neto gravado {pesos(arca.neto_gravado)}, IVA {pesos(arca.iva)} y total {pesos(arca.total)}, pero no trae el detalle por alícuota: cargá abajo la base de cada alícuota. El código de autorización {arca.cae || '—'} ya cuenta como respaldo, así que no hace falta la imagen.</Alerta>
      )}
      {error && <Alerta tipo="error"><strong>{error.codigo.replace(/_/g, ' ').toLowerCase()}</strong><p>{error.detalle}</p></Alerta>}

      <div className="panel form-p">
        <div className="panel-h"><h2>Datos del comprobante</h2><span className="tag-prueba">PRUEBA</span></div>
        <div className="grid-form">
          <Campo etiqueta="Proveedor" ancho error={campoError('contraparte_id')}
            ayuda={proveedor ? (proveedor.completo ? <span className="mono">CUIT {proveedor.documento} · {proveedor.condicion_desc}</span>
              : <span className="mal-t">Sin CUIT o condición de IVA: completalo en Proveedores.</span>) : <Link href="/proveedores">¿No está? Agregalo en Proveedores</Link>}>
            <select className="in" value={f.contraparte_id} onChange={(e) => setF({ ...f, contraparte_id: e.target.value })}>
              <option value="">Elegí un proveedor…</option>
              {proveedores.datos?.map((p) => <option key={p.id} value={p.id}>{p.nombre}{p.completo ? '' : ' (sin CUIT)'}</option>)}
            </select>
          </Campo>
          <Campo etiqueta="Tipo" error={campoError('tipo')} ayuda={!tipo.discrimina_iva ? 'No da crédito fiscal: el total va como no gravado.' : undefined}>
            <select className="in" value={f.tipo} onChange={(e) => setF({ ...f, tipo: Number(e.target.value) })}>
              {tiposCompra.map((t) => <option key={t.codigo} value={t.codigo}>{t.descripcion}</option>)}
            </select>
          </Campo>
          <Campo etiqueta="Punto de venta" error={campoError('punto_venta')}>
            <input className="in num-in" inputMode="numeric" placeholder="00005" value={f.punto_venta} onChange={(e) => setF({ ...f, punto_venta: e.target.value.replace(/\D/g, '') })} />
          </Campo>
          <Campo etiqueta="Número" error={campoError('numero')}>
            <input className="in num-in" inputMode="numeric" placeholder="00001234" value={f.numero} onChange={(e) => setF({ ...f, numero: e.target.value.replace(/\D/g, '') })} />
          </Campo>
          <Campo etiqueta="Fecha del comprobante" error={campoError('fecha')}>
            <input className="in" type="date" value={f.fecha} onChange={(e) => setF({ ...f, fecha: e.target.value })} />
          </Campo>
          <Campo etiqueta="Período de IVA" error={campoError('periodo')} ayuda={periodoManual ? 'Imputada a otro mes.' : 'Por defecto, el mes de la fecha.'}>
            <input className="in" type="month" value={periodoManual ? f.periodo : f.fecha.slice(0, 7)} onChange={(e) => { setPeriodoManual(true); setF({ ...f, periodo: e.target.value }); }} />
          </Campo>
          <Campo etiqueta="Vence el pago"><input className="in" type="date" value={f.vencimiento_pago} onChange={(e) => setF({ ...f, vencimiento_pago: e.target.value })} /></Campo>
          <Campo etiqueta="CAE (opcional)" error={campoError('cae')}><input className="in mono" inputMode="numeric" maxLength={14} value={f.cae} onChange={(e) => setF({ ...f, cae: e.target.value.replace(/\D/g, '') })} /></Campo>
          <Campo etiqueta="Otra orden de compra (solo si no aparece en la lista de abajo)"><input className="in" placeholder="Número de la orden de compra del CRM" value={f.orden_compra} onChange={(e) => setF({ ...f, orden_compra: e.target.value })} /></Campo>
          <Campo etiqueta="Presupuesto de venta (referencia)"><input className="in" value={f.presupuesto} onChange={(e) => setF({ ...f, presupuesto: e.target.value })} /></Campo>
        </div>

        {tipo.clase === 'factura' && (
          <>
            <h3>Orden de compra o categoría de gasto</h3>
            {!f.contraparte_id ? <p className="nota">Elegí el proveedor para ver sus órdenes de compra recibidas.</p>
              : ordenes.datos?.length ? (
                <div className="tabla-wrap"><table className="tabla">
                  <thead><tr><th className="chk"><span className="sr">Elegir</span></th><th>Orden de compra</th><th>Presupuesto de venta</th><th>Recibida</th><th className="num">Importe</th><th className="num">Saldo sin facturar</th></tr></thead>
                  <tbody>{ordenes.datos.map((o) => (
                    <tr key={o.id}>
                      <td className="chk"><input type="checkbox" aria-label={`Vincular la orden ${o.numero}`} checked={ordenesSel.includes(o.id)}
                        onChange={(e) => setOrdenesSel(e.target.checked ? [...ordenesSel, o.id] : ordenesSel.filter((x) => x !== o.id))} /></td>
                      <td className="mono">{o.numero}<small>{o.descripcion}</small></td><td className="mono">{o.presupuesto}</td>
                      <td className="mono">{o.fecha_recepcion ? fecha(o.fecha_recepcion) : '—'}</td>
                      <td className="num">{pesos(o.importe)}</td><td className="num">{pesos(o.saldo)}</td>
                    </tr>))}
                  </tbody>
                </table></div>
              ) : <p className="nota">Este proveedor no tiene órdenes de compra recibidas con saldo en {emp.nombre_corto}.</p>}
            {catCompras.datos && (
              <p className="nota">Tolerancia de precio: el menor entre {String(catCompras.datos.tolerancia.porcentaje).replace('.', ',')} % y {pesos(catCompras.datos.tolerancia.importe)}. Lo define la empresa.
                Si la factura sin IVA se pasa del saldo de sus órdenes, queda en revisión hasta que la apruebe Contador o Gerencia.</p>
            )}
            <div className="grid-form">
              <Campo etiqueta="Categoría de gasto (obligatoria si no hubo orden de compra)" error={campoError('categoria')}>
                <select className="in" value={categoria} onChange={(e) => setCategoria(e.target.value)}>
                  <option value="">Sin categoría</option>
                  {catCompras.datos?.categorias.map((x) => <option key={x} value={x}>{x}</option>)}
                </select>
              </Campo>
            </div>
          </>
        )}

        <h3>Leyendas del proveedor</h3>
        <div className="grid-form">
          <label className="filtro"><input type="checkbox" checked={leyendas.cbu_informada} onChange={(e) => setLeyendas({ ...leyendas, cbu_informada: e.target.checked })} /> La factura informa el CBU del proveedor</label>
          <label className="filtro"><input type="checkbox" checked={leyendas.sujeta_retencion} onChange={(e) => setLeyendas({ ...leyendas, sujeta_retencion: e.target.checked })} /> La factura dice que está sujeta a retención</label>
          {Number((extras.percepcion_iibb || '0').replace(',', '.')) > 0 && (
            <Campo etiqueta="Jurisdicción de la percepción de Ingresos Brutos" error={campoError('jurisdiccion_iibb')}>
              <select className="in" value={jurisdiccion} onChange={(e) => setJurisdiccion(e.target.value)}>
                <option value="">Córdoba (por defecto)</option>
                {catCompras.datos?.jurisdicciones.map((x) => <option key={x} value={x}>{x}</option>)}
              </select>
            </Campo>
          )}
        </div>

        {tipo.clase !== 'factura' && (
          <div className="grid-form">
            <Campo etiqueta="Factura que corrige" ancho error={campoError('asociado_id')}>
              <select className="in" value={f.asociado_id} onChange={(e) => setF({ ...f, asociado_id: e.target.value })}>
                <option value="">Elegí la factura…</option>
                {facturasProveedor.map((c) => <option key={c.id} value={c.id}>{c.tipo_desc} {c.numero_texto} · {pesos(c.total)}</option>)}
              </select>
            </Campo>
            <Campo etiqueta="Motivo" ancho error={campoError('motivo')}><input className="in" value={f.motivo} onChange={(e) => setF({ ...f, motivo: e.target.value })} /></Campo>
          </div>
        )}

        <h3>Desglose</h3>
        {tipo.discrimina_iva ? (
          <div className="desglose-f">
            {desglose.map((d, i) => (
              <div className="fila-ali" key={i}>
                <select className="in" value={d.alicuota_codigo} onChange={(e) => setDesglose(desglose.map((x, j) => (j === i ? { ...x, alicuota_codigo: Number(e.target.value) } : x)))}>
                  {catalogos!.alicuotas.map((a) => <option key={a.codigo} value={a.codigo}>{a.descripcion}</option>)}
                </select>
                <input className="in num-in" inputMode="decimal" placeholder="Base imponible" value={d.base} onChange={(e) => setDesglose(desglose.map((x, j) => (j === i ? { ...x, base: e.target.value } : x)))} />
                <button className="btn ghost chico" aria-label="Quitar" disabled={desglose.length === 1} onClick={() => setDesglose(desglose.filter((_, j) => j !== i))}><Icono n="cruz" t={14} /></button>
              </div>
            ))}
            <button className="btn chico" onClick={() => setDesglose([...desglose, { alicuota_codigo: 4, base: '' }])}><Icono n="mas" t={14} /> Agregar alícuota</button>
          </div>
        ) : <p className="nota">Una {tipo.descripcion} no discrimina IVA: cargá el total en «No gravado».</p>}
        <div className="grid-form">
          {EXTRAS.map(([k, t]) => (
            <Campo key={k} etiqueta={t}><input className="in num-in" inputMode="decimal" placeholder="0,00" value={extras[k]} onChange={(e) => setExtras({ ...extras, [k]: e.target.value })} /></Campo>
          ))}
        </div>
        {errorCalc && <p className="campo-msg">{errorCalc}</p>}

        <h3>Imagen o PDF de la factura</h3>
        <div className="adj">
          {imagen ? (
            <div className="adj-v">
              {imagen.url && !imagen.pdf ? <img className="adj-img" src={imagen.url} alt="Factura del proveedor" /> : <div className="adj-pdf"><Icono n="archivo" t={30} />PDF</div>}
              <div className="adj-m"><strong>{imagen.nombre}</strong><small>{imagen.path}</small>
                <div className="adj-acc"><button className="btn chico" onClick={() => setImagen(null)}>Cambiar archivo</button></div></div>
            </div>
          ) : (
            <label className="archivo btn" style={{ justifySelf: 'start' }}>
              <Icono n="subir" /> {subiendo ? 'Subiendo…' : 'Subir imagen o PDF'}
              <input type="file" accept="image/png,image/jpeg,image/webp,application/pdf" hidden onChange={(e) => elegirArchivo(e.target.files?.[0])} />
            </label>
          )}
          {error?.campo === 'imagen' && <span className="campo-msg">{error.detalle}</span>}
          <span className="nota">Para confirmar hace falta la imagen, el CAE o el código de autorización de ARCA. Una vez guardada, la imagen no se puede reemplazar ni borrar.</span>
        </div>

        <div className="totales">
          <table className="mini"><thead><tr><th>Alícuota</th><th className="num">Base</th><th className="num">IVA</th></tr></thead>
            <tbody>{calc?.desglose.map((d) => <tr key={d.alicuota_codigo}><td>{String(d.porcentaje).replace('.', ',')} %</td><td className="num">{pesos(d.base)}</td><td className="num">{pesos(d.iva)}</td></tr>)}</tbody>
          </table>
          <dl className="resumen">
            <div><dt>Neto gravado</dt><dd>{pesos(calc?.importes.neto_gravado)}</dd></div>
            <div><dt>IVA (crédito fiscal)</dt><dd>{pesos(calc?.importes.iva)}</dd></div>
            {EXTRAS.filter(([k]) => Number(calc?.importes[k])).map(([k, t]) => <div key={k}><dt>{t}</dt><dd>{pesos(calc?.importes[k])}</dd></div>)}
            <div className="gr"><dt>Total</dt><dd>{pesos(calc?.importes.total)}</dd></div>
          </dl>
        </div>
      </div>

      <div className="barra-fija">
        <div className="bf-t"><span>Total de la factura</span><b>{pesos(calc?.importes.total)}</b></div>
        <div className="bf-b">
          <button className="btn" disabled={enviando || subiendo} onClick={() => guardar(false)}>Guardar borrador</button>
          <button className="btn primario" disabled={enviando || subiendo} onClick={() => guardar(true)}>Confirmar</button>
        </div>
      </div>
    </>
  );
}
