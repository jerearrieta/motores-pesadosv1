-- =====================================================================
-- Resumen y ajustes para IVA Simple (RG 5705). Port de resumenIvaSimple
-- del Simulador Libro de IVA (nucleo.js, sección 13). El Excel lo arma
-- el front con estos datos; el nombre del archivo empieza con BORRADOR_.
-- También: parámetros con fecha de vigencia y jurisdicción de Ingresos
-- Brutos de las percepciones sufridas (US-112).
-- =====================================================================

-- Parámetros con fecha de vigencia (R0.4): vale el de fecha más reciente que no sea posterior a la consultada
create table fiscal.parametro (
  clave          text not null,
  vigente_desde  date not null,
  valor          jsonb not null,
  fuente         text not null default '',
  primary key (clave, vigente_desde)
);
revoke all on fiscal.parametro from public;

insert into fiscal.parametro (clave, vigente_desde, valor, fuente) values
  ('tolerancia_orden_compra', '2026-01-01', '{"porcentaje": 2.00, "importe": 5000.00}', 'D4.1 (valor de ejemplo, lo define la empresa)'),
  ('identificar_consumidor_final', '2026-07-01', '{"desde": 10000000.00}', 'RG 5866'),
  ('computo_percepciones_iva', '2025-09-01', '{"periodos_siguientes": 5}', 'RG 5750');

create or replace function fiscal.parametro_vigente(p_clave text, p_fecha date default current_date)
returns jsonb language sql stable as $$
  select p.valor || jsonb_build_object('fuente', p.fuente, 'vigente_desde', p.vigente_desde)
  from fiscal.parametro p where p.clave = p_clave and p.vigente_desde <= coalesce(p_fecha, current_date)
  order by p.vigente_desde desc limit 1
$$;

-- Jurisdicción de la percepción de Ingresos Brutos sufrida (US-112)
alter table fiscal.comprobante add column jurisdiccion_iibb text not null default '';

-- Neto e IVA por alícuota a partir de los totales de un libro
create or replace function fiscal.iva_por_alicuota(p_totales jsonb)
returns jsonb language sql immutable as $$
  select coalesce(jsonb_agg(jsonb_build_object('alicuota', a, 'neto', n, 'iva', i) order by o), '[]')
  from (values
    (1, '21 %', (p_totales->>'n21')::numeric, (p_totales->>'i21')::numeric),
    (2, '10,5 %', (p_totales->>'n105')::numeric, (p_totales->>'i105')::numeric),
    (3, '27 %', (p_totales->>'n27')::numeric, (p_totales->>'i27')::numeric),
    (4, '5 % y 2,5 %', (p_totales->>'n_otras')::numeric, (p_totales->>'i_otras')::numeric),
    (5, '0 %', (p_totales->>'n0')::numeric, 0::numeric)) v(o, a, n, i)
  where n <> 0 or i <> 0
$$;

create or replace function public.resumen_iva_simple(p_empresa text, p_periodo text)
returns jsonb language plpgsql stable security definer set search_path = fiscal, pg_temp as $$
declare
  v_par jsonb;
  v_ajustes jsonb;
begin
  perform fiscal.req(exists (select 1 from fiscal.empresa where id = p_empresa), 'NO_ENCONTRADO', 'La empresa no existe.');
  perform fiscal.req(p_periodo ~ '^\d{4}-(0[1-9]|1[0-2])$', 'VALIDACION', 'El período no es válido.', 'periodo');
  v_par := fiscal.parametro_vigente('computo_percepciones_iva', (p_periodo || '-01')::date);
  select coalesce(jsonb_agg(jsonb_build_object('tipo', a.tipo, 'comprobante', a.comprobante, 'contraparte', a.contraparte, 'detalle', a.detalle, 'importe', a.importe)
                            order by a.orden, a.fecha, a.comprobante), '[]')
  into v_ajustes
  from (
    select 1 as orden, c.fecha, 'Crédito fiscal imputado a otro período' as tipo, fiscal.etiqueta(c) as comprobante, c.contraparte_razon as contraparte,
      format('Fecha %s · imputada a %s', to_char(c.fecha, 'DD/MM/YYYY'), c.periodo) as detalle, c.iva as importe
    from fiscal.comprobante c
    where c.empresa_id = p_empresa and c.operacion = 'compra' and c.estado = 'confirmada' and c.periodo <> to_char(c.fecha, 'YYYY-MM')
      and (c.periodo = p_periodo or to_char(c.fecha, 'YYYY-MM') = p_periodo)
    union all
    select 2, f.fecha, format('Percepción de IVA sufrida (computable en este período o en los %s siguientes, %s)', v_par->>'periodos_siguientes', v_par->>'fuente'),
      f.tipo_desc || ' ' || f.numero, f.contraparte, '', f.perc_iva
    from fiscal.libro_filas(p_empresa, p_periodo, 'compra') f where f.perc_iva <> 0
    union all
    select 3, f.fecha, 'Percepción de Ingresos Brutos sufrida (no va en IVA Simple; es para la declaración jurada de Ingresos Brutos)',
      f.tipo_desc || ' ' || f.numero, f.contraparte, 'Jurisdicción: ' || coalesce(nullif(c.jurisdiccion_iibb, ''), 'sin informar'), f.perc_iibb
    from fiscal.libro_filas(p_empresa, p_periodo, 'compra') f join fiscal.comprobante c on c.id = f.id where f.perc_iibb <> 0
    union all
    select 4, c.fecha, 'Compra anulada en el sistema: excluirla si ARCA la precarga', fiscal.etiqueta(c), c.contraparte_razon, c.motivo_anulacion, c.iva
    from fiscal.comprobante c
    where c.empresa_id = p_empresa and c.operacion = 'compra' and c.estado = 'anulada' and to_char(c.fecha, 'YYYY-MM') = p_periodo
    union all
    select 5, f.fecha, 'Comprobante B o C: no da crédito fiscal', f.tipo_desc || ' ' || f.numero, f.contraparte, 'Su importe va como no gravado', 0
    from fiscal.libro_filas(p_empresa, p_periodo, 'compra') f join fiscal.tipo_comprobante t on t.codigo = f.tipo where not t.discrimina_iva
  ) a;
  return jsonb_build_object(
    'periodo', p_periodo,
    'debito', fiscal.iva_por_alicuota(fiscal.libro_json(p_empresa, p_periodo, 'venta')->'totales'),
    'credito', fiscal.iva_por_alicuota(fiscal.libro_json(p_empresa, p_periodo, 'compra')->'totales'),
    'posicion', fiscal.posicion(p_empresa, p_periodo),
    'ajustes', v_ajustes,
    -- La hoja de diferencias va solo si se concilió este mismo período
    'conciliaciones', (select jsonb_agg(jsonb_build_object('tipo', t.tipo, 'cuando', k.cuando, 'archivo', k.archivo, 'resumen', k.resumen,
                         'diferencias', coalesce(k.diferencias, '[]'::jsonb)) order by t.o)
                       from (values (1, 'emitidos'), (2, 'recibidos')) t(o, tipo)
                       left join fiscal.conciliacion_arca k on k.empresa_id = p_empresa and k.periodo = p_periodo and k.tipo_archivo = t.tipo));
end $$;

do $$
begin
  revoke all on function public.resumen_iva_simple(text, text) from public;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    grant execute on function public.resumen_iva_simple(text, text) to anon, authenticated;
  end if;
end $$;
