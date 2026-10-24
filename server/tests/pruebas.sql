-- =====================================================================
-- Pruebas del backend. Corren dentro de una transacción que se deshace
-- al final, así que no dejan rastro. Uso: server/tests/correr.sh
-- Los valores esperados son la "verdad de referencia" del Simulador.
-- =====================================================================
\set ON_ERROR_STOP 1
\o /dev/null
begin;

create temp table resultado (n serial, prueba text, ok boolean, detalle text);

create function pg_temp.ok(p_nombre text, p_cond boolean, p_detalle text default '')
returns void language sql as $$ insert into resultado (prueba, ok, detalle) values (p_nombre, coalesce(p_cond, false), p_detalle) $$;

create function pg_temp.igual(p_nombre text, p_obtenido anyelement, p_esperado anyelement)
returns void language sql as $$
  insert into resultado (prueba, ok, detalle) values (p_nombre, p_obtenido is not distinct from p_esperado,
    format('esperado %s, obtenido %s', p_esperado, p_obtenido))
$$;

-- Ejecuta p_sql y espera que falle con el código de negocio p_codigo
create function pg_temp.falla(p_nombre text, p_sql text, p_codigo text)
returns void language plpgsql as $$
begin
  begin
    execute p_sql;
    insert into resultado (prueba, ok, detalle) values (p_nombre, false, 'no falló');
  exception when others then
    insert into resultado (prueba, ok, detalle) values (p_nombre, sqlerrm = p_codigo, format('esperado %s, obtenido %s (%s)', p_codigo, sqlerrm, sqlstate));
  end;
end $$;

-- ---------------------------------------------------------------------
-- 1. Cálculo
-- ---------------------------------------------------------------------
select pg_temp.igual('IVA 21 % de 800.000,00', fiscal.calcular_iva(800000.00, 21), 168000.00);
select pg_temp.igual('Redondeo mitad hacia arriba: 10,50 al 21 %', fiscal.calcular_iva(10.50, 21), 2.21);
select pg_temp.igual('Redondeo: 0,10 al 21 %', fiscal.calcular_iva(0.10, 21), 0.02);
select pg_temp.igual('IVA sobre la suma de netos, no línea por línea (3 × 0,50 al 21 % = 0,32)',
  (public.calcular_comprobante('{"operacion":"venta","lineas":[
     {"descripcion":"a","cantidad":"1","precio":"0.50","alicuota_codigo":5},
     {"descripcion":"b","cantidad":"1","precio":"0.50","alicuota_codigo":5},
     {"descripcion":"c","cantidad":"1","precio":"0.50","alicuota_codigo":5}]}')->'importes'->>'iva')::numeric, 0.32);
select pg_temp.igual('Importe de línea: 2,5 × 19,99 = 49,98',
  (public.calcular_comprobante('{"operacion":"venta","lineas":[{"descripcion":"x","cantidad":"2.5","precio":"19.99","alicuota_codigo":5}]}')->'items'->0->>'importe_neto')::numeric, 49.98);
select pg_temp.igual('Descuento: 4 × 12.500 con 5 % = 47.500,00',
  (public.calcular_comprobante('{"operacion":"venta","lineas":[{"descripcion":"x","cantidad":"4","precio":"12500","descuento":"5","alicuota_codigo":5}]}')->'importes'->>'neto_gravado')::numeric, 47500.00);
select pg_temp.igual('Precio final 100.000 con IVA 21 %: neto 82.644,63',
  (public.calcular_comprobante('{"operacion":"venta","modo":"precio_final","lineas":[{"descripcion":"x","total":"100000","alicuota_codigo":5}]}')->'importes'->>'neto_gravado')::numeric, 82644.63);
select pg_temp.igual('Precio final: el total es exactamente lo cobrado',
  (public.calcular_comprobante('{"operacion":"venta","modo":"precio_final","lineas":[{"descripcion":"x","total":"100000","alicuota_codigo":5}]}')->'importes'->>'total')::numeric, 100000.00);
select pg_temp.igual('Factura modelo: 805.784,46 + IVA 21 % = 974.999,20',
  (public.calcular_comprobante('{"operacion":"venta","lineas":[{"descripcion":"x","cantidad":"1","precio":"805784.46","alicuota_codigo":5}]}')->'importes'->>'total')::numeric, 974999.20);
select pg_temp.igual('Compra con dos alícuotas y percepciones',
  (public.calcular_comprobante('{"operacion":"compra","tipo":1,"desglose":[{"alicuota_codigo":5,"base":"500000"},{"alicuota_codigo":4,"base":"100000"}],
     "percepcion_iva":"18000","percepcion_iibb":"12000"}')->'importes'->>'total')::numeric, 745500.00);
select pg_temp.falla('Una compra C no discrimina IVA',
  $$select public.calcular_comprobante('{"operacion":"compra","tipo":11,"desglose":[{"alicuota_codigo":5,"base":"1000"}]}')$$, 'IVA_SIN_CREDITO');
select pg_temp.falla('Importe con tres decimales se rechaza',
  $$select public.calcular_comprobante('{"operacion":"compra","tipo":1,"desglose":[{"alicuota_codigo":5,"base":"10.123"}]}')$$, 'VALIDACION');

-- ---------------------------------------------------------------------
-- 2. CUIT
-- ---------------------------------------------------------------------
select pg_temp.ok('CUIT de prueba válidos', bool_and(fiscal.cuit_valido(c)))
from unnest(array['30999999901', '30999999804', '30999999928', '30999999936', '33999999943', '30999999952', '27999999986']) c;
select pg_temp.ok('CUIT mal escritos inválidos', not bool_or(fiscal.cuit_valido(c)))
from unnest(array['30999999900', '3099999990', '3099999990a', '', '12345678']) c;

-- ---------------------------------------------------------------------
-- 3. Libro y posición con los datos de ejemplo (verdad de referencia)
-- ---------------------------------------------------------------------
select pg_temp.igual('Ventas oct: neto 21 %', (public.libro_iva('MP', '2026-10', 'venta')->'totales'->>'n21')::numeric, 1002644.63);
select pg_temp.igual('Ventas oct: IVA 21 %', (public.libro_iva('MP', '2026-10', 'venta')->'totales'->>'i21')::numeric, 210555.37);
select pg_temp.igual('Ventas oct: neto 10,5 %', (public.libro_iva('MP', '2026-10', 'venta')->'totales'->>'n105')::numeric, 40000.00);
select pg_temp.igual('Ventas oct: IVA 10,5 %', (public.libro_iva('MP', '2026-10', 'venta')->'totales'->>'i105')::numeric, 4200.00);
select pg_temp.igual('Ventas oct: débito fiscal', (public.libro_iva('MP', '2026-10', 'venta')->'totales'->>'iva')::numeric, 214755.37);
select pg_temp.igual('Ventas oct: total', (public.libro_iva('MP', '2026-10', 'venta')->'totales'->>'total')::numeric, 1257400.00);
select pg_temp.igual('Ventas oct: el borrador no entra (4 comprobantes)', (public.libro_iva('MP', '2026-10', 'venta')->'totales'->>'cantidad')::int, 4);
select pg_temp.igual('Compras oct: neto 21 %', (public.libro_iva('MP', '2026-10', 'compra')->'totales'->>'n21')::numeric, 450000.00);
select pg_temp.igual('Compras oct: IVA 21 %', (public.libro_iva('MP', '2026-10', 'compra')->'totales'->>'i21')::numeric, 94500.00);
select pg_temp.igual('Compras oct: neto 10,5 %', (public.libro_iva('MP', '2026-10', 'compra')->'totales'->>'n105')::numeric, 120000.00);
select pg_temp.igual('Compras oct: IVA 10,5 %', (public.libro_iva('MP', '2026-10', 'compra')->'totales'->>'i105')::numeric, 12600.00);
select pg_temp.igual('Compras oct: no gravado', (public.libro_iva('MP', '2026-10', 'compra')->'totales'->>'no_gravado')::numeric, 51000.00);
select pg_temp.igual('Compras oct: percepción IIBB', (public.libro_iva('MP', '2026-10', 'compra')->'totales'->>'perc_iibb')::numeric, 7500.00);
select pg_temp.igual('Compras oct: crédito fiscal', (public.libro_iva('MP', '2026-10', 'compra')->'totales'->>'iva')::numeric, 107100.00);
select pg_temp.igual('Compras oct: total', (public.libro_iva('MP', '2026-10', 'compra')->'totales'->>'total')::numeric, 735600.00);
select pg_temp.igual('Posición oct: débito', (public.posicion_iva('MP', '2026-10')->>'debito')::numeric, 214755.37);
select pg_temp.igual('Posición oct: crédito', (public.posicion_iva('MP', '2026-10')->>'credito')::numeric, 107100.00);
select pg_temp.igual('Posición oct: saldo a pagar', (public.posicion_iva('MP', '2026-10')->>'saldo')::numeric, 107655.37);
select pg_temp.igual('Posición nov: débito', (public.posicion_iva('MP', '2026-11')->>'debito')::numeric, 21000.00);
select pg_temp.igual('Posición nov: crédito', (public.posicion_iva('MP', '2026-11')->>'credito')::numeric, 42000.00);
select pg_temp.igual('Posición nov: saldo a favor', (public.posicion_iva('MP', '2026-11')->>'saldo')::numeric, -21000.00);
select pg_temp.igual('RMP no se mezcla con MP', (public.posicion_iva('RMP', '2026-10')->>'debito')::numeric, 0::numeric);
select pg_temp.igual('Numeración: la Factura A de noviembre es la 3', (select numero from fiscal.comprobante where operacion = 'venta' and tipo = 1 and fecha = '2026-11-03'), 3);
select pg_temp.igual('Exportación con columnas del Excel', (select count(*)::int from jsonb_array_elements(public.exportar_facturas('MP', '2026-10'))), 9);

-- ---------------------------------------------------------------------
-- 3b. Conciliación con ARCA (valores de probar-nucleo.js, pruebasArca).
-- Corre sobre los datos de ejemplo limpios y deshace todo lo que cambia:
-- los resultados se juntan en una variable y se guardan después.
-- ---------------------------------------------------------------------
select pg_temp.igual('CSV con punto y coma, comillas y la marca de orden de bytes',
  fiscal.parsear_csv(chr(65279) || 'a;"b;c";"d ""e"""' || E'\r\n1;2;3\r\n'), '[["a", "b;c", "d \"e\""], ["1", "2", "3"]]'::jsonb);
select pg_temp.igual('Importes escritos de distintas formas',
  array(select fiscal.importe_flexible(x) from unnest(array['1.234,56', '1,234.56', '612500', '-36.300,00', '12,5', '(150,00)', '$ 1.500']) x),
  array[1234.56, 1234.56, 612500.00, -36300.00, 12.50, -150.00, 1500.00]::numeric[]);
select pg_temp.falla('Lectura no importa desde ARCA', $$select public.importar_desde_arca('lectura', 'MP', 'recibidos', '[]')$$, 'PROHIBIDO');

do $$
declare
  r jsonb := '[]';
  v_csv text := public.archivo_ejemplo_arca('MP', '2026-10', 'recibidos');
  v jsonb; c jsonb; imp jsonb; conf jsonb; v2 jsonb;
  f jsonb; m jsonb;
begin
  begin
    v := public.conciliar_arca('administracion', 'MP', '2026-10', 'recibidos', 'ejemplo.csv', v_csv);
    r := r || jsonb_build_object('p', 'Lee el archivo de ejemplo de recibidos: 0 errores y 8 comprobantes',
      'ok', jsonb_array_length(v->'lectura'->'errores') = 0 and (v->'lectura'->>'cantidad')::int = 8, 'd', v->'lectura');
    select x into f from jsonb_array_elements(v->'comprobantes') x where (x->>'numero')::int = 4567;
    select x into m from jsonb_array_elements(v->'comprobantes') x where (x->>'numero')::int = 1310;
    r := r || jsonb_build_object('p', 'Detecta la alícuota del 27 % sin detalle, y avisa cuando no corresponde a una sola',
      'ok', (f->'desglose'->0->>'alicuota_codigo')::int = 6 and (f->'desglose'->0->>'base')::numeric = 35000 and m->'desglose' = 'null'::jsonb
            and jsonb_array_length(m->'observaciones') = 1, 'd', jsonb_build_array(f->'desglose', m->'desglose', m->'observaciones'));
    c := v->'conciliacion'->'resumen';
    r := r || jsonb_build_object('p', 'Compras de octubre de Mecánica Pesada: 3 coinciden, 1 difiere, 4 faltan en el sistema, 0 faltan en ARCA',
      'ok', array[(c->>'coincide')::int, (c->>'difiere')::int, (c->>'falta_sistema')::int, (c->>'falta_arca')::int] = array[3, 1, 4, 0], 'd', c);
    r := r || jsonb_build_object('p', 'La que difiere es la Factura A 00005-00001250, por la fecha',
      'ok', exists (select 1 from jsonb_array_elements(v->'conciliacion'->'filas') x where x->>'estado' = 'difiere'
                    and x->>'etiqueta' = 'Factura A 00005-00001250' and x->'detalle'->>0 like 'Fecha:%'), 'd', '');
    r := r || jsonb_build_object('p', 'La conciliación queda registrada para el cierre',
      'ok', exists (select 1 from fiscal.conciliacion_arca where empresa_id = 'MP' and periodo = '2026-10' and tipo_archivo = 'recibidos'), 'd', '');
    imp := public.importar_desde_arca('administracion', 'MP', 'recibidos',
      (select jsonb_agg(x->'arca') from jsonb_array_elements(v->'conciliacion'->'filas') x where x->>'estado' = 'falta_sistema' and (x->>'importable')::boolean));
    r := r || jsonb_build_object('p', 'Importa 3 compras como borrador, sin errores',
      'ok', jsonb_array_length(imp->'creados') = 3 and jsonb_array_length(imp->'errores') = 0
            and not exists (select 1 from jsonb_array_elements(imp->'creados') x where x->>'estado' <> 'borrador'), 'd', imp);
    r := r || jsonb_build_object('p', 'Crea el proveedor que no estaba (Servicios Eléctricos Ejemplo S.A.)',
      'ok', exists (select 1 from fiscal.contraparte where numero_doc = '30999999960' and es_proveedor), 'd', '');
    conf := public.confirmar_importadas('administracion', 'MP');
    r := r || jsonb_build_object('p', 'Confirma las 3 importadas con el código de autorización de ARCA',
      'ok', jsonb_array_length(conf->'ok') = 3 and jsonb_array_length(conf->'pendientes') = 0, 'd', conf);
    v2 := public.conciliar_arca('administracion', 'MP', '2026-10', 'recibidos', 'ejemplo.csv', v_csv);
    c := v2->'conciliacion'->'resumen';
    r := r || jsonb_build_object('p', 'Después de importar y confirmar: 6 coinciden y queda 1 para cargar a mano',
      'ok', array[(c->>'coincide')::int, (c->>'difiere')::int, (c->>'falta_sistema')::int] = array[6, 1, 1], 'd', c);
    c := v2->'conciliacion';
    r := r || jsonb_build_object('p', 'La diferencia con ARCA es la factura de 115.750,00 (100.000,00 de neto y 15.750,00 de IVA)',
      'ok', array[(c->'tot_arca'->>'neto')::numeric - (c->'tot_sistema'->>'neto')::numeric, (c->'tot_arca'->>'iva')::numeric - (c->'tot_sistema'->>'iva')::numeric,
                  (c->'tot_arca'->>'total')::numeric - (c->'tot_sistema'->>'total')::numeric] = array[100000.00, 15750.00, 115750.00]::numeric[],
      'd', jsonb_build_array(c->'tot_arca', c->'tot_sistema'));
    r := r || jsonb_build_object('p', 'El crédito fiscal de octubre suma las compras importadas',
      'ok', (public.posicion_iva('MP', '2026-10')->>'credito')::numeric = 107100.00 + 37800.00 + 8400.00 + 9450.00, 'd', public.posicion_iva('MP', '2026-10'));
    -- Emitidos: la factura del sistema anterior se importa como histórico
    v := public.conciliar_arca('contador', 'MP', '2026-10', 'emitidos', 'ejemplo-emitidos.csv', public.archivo_ejemplo_arca('MP', '2026-10', 'emitidos'));
    c := v->'conciliacion'->'resumen';
    r := r || jsonb_build_object('p', 'Ventas de octubre: todo coincide salvo la factura del sistema anterior, que falta en el sistema',
      'ok', (c->>'falta_sistema')::int = 1 and (c->>'difiere')::int = 0 and (c->>'falta_arca')::int = 0 and (c->>'coincide')::int > 0, 'd', c);
    imp := public.importar_desde_arca('contador', 'MP', 'emitidos',
      (select jsonb_agg(x->'arca') from jsonb_array_elements(v->'conciliacion'->'filas') x where x->>'estado' = 'falta_sistema'));
    r := r || jsonb_build_object('p', 'La venta del sistema anterior queda como histórico autorizado',
      'ok', jsonb_array_length(imp->'creados') = 1 and imp->'creados'->0->>'estado' = 'autorizado', 'd', imp);
    c := public.conciliar_arca('contador', 'MP', '2026-10', 'emitidos', 'ejemplo-emitidos.csv', public.archivo_ejemplo_arca('MP', '2026-10', 'emitidos'))->'conciliacion'->'resumen';
    r := r || jsonb_build_object('p', 'Después de importarla, no falta ninguna venta', 'ok', (c->>'falta_sistema')::int = 0, 'd', c);
    raise exception 'DESHACER';
  exception when raise_exception then
    if sqlerrm <> 'DESHACER' then raise; end if;
  end;
  insert into resultado (prueba, ok, detalle) select x->>'p', coalesce((x->>'ok')::boolean, false), x->>'d' from jsonb_array_elements(r) x;
end $$;
select pg_temp.igual('Los datos de ejemplo quedan como estaban después de las pruebas de ARCA',
  (public.posicion_iva('MP', '2026-10')->>'credito')::numeric, 107100.00);

-- ---------------------------------------------------------------------
-- 3c. Resumen y ajustes para IVA Simple (octubre de Mecánica Pesada)
-- ---------------------------------------------------------------------
select pg_temp.igual('IVA Simple: la posición sigue la verdad de referencia (débito, crédito y a pagar)',
  array[(public.resumen_iva_simple('MP', '2026-10')->'posicion'->>'debito')::numeric, (public.resumen_iva_simple('MP', '2026-10')->'posicion'->>'credito')::numeric,
        (public.resumen_iva_simple('MP', '2026-10')->'posicion'->>'saldo')::numeric], array[214755.37, 107100.00, 107655.37]);
select pg_temp.igual('IVA Simple: el débito por alícuota suma el débito del libro',
  (select sum((x->>'iva')::numeric) from jsonb_array_elements(public.resumen_iva_simple('MP', '2026-10')->'debito') x), 214755.37);
select pg_temp.igual('IVA Simple: el crédito por alícuota suma el crédito del libro',
  (select sum((x->>'iva')::numeric) from jsonb_array_elements(public.resumen_iva_simple('MP', '2026-10')->'credito') x), 107100.00);
select pg_temp.igual('IVA Simple: ajustes de octubre (percepción de Ingresos Brutos y factura C)',
  (select array_agg(x->>'tipo' order by n) from jsonb_array_elements(public.resumen_iva_simple('MP', '2026-10')->'ajustes') with ordinality e(x, n)),
  array['Percepción de Ingresos Brutos sufrida (no va en IVA Simple; es para la declaración jurada de Ingresos Brutos)', 'Comprobante B o C: no da crédito fiscal']);
select pg_temp.ok('IVA Simple: sin conciliar, no hay diferencias con ARCA',
  not exists (select 1 from jsonb_array_elements(public.resumen_iva_simple('MP', '2026-10')->'conciliaciones') x where x->>'cuando' is not null));
select pg_temp.igual('Parámetro con fecha de vigencia: tolerancia de la orden de compra',
  fiscal.parametro_vigente('tolerancia_orden_compra', '2026-10-21')->>'importe', '5000.00');
select pg_temp.ok('Parámetro antes de su vigencia: no hay valor', fiscal.parametro_vigente('identificar_consumidor_final', '2026-06-30') is null);
do $$
declare r jsonb := '[]'; v jsonb;
begin
  begin
    perform public.conciliar_arca('contador', 'MP', '2026-10', 'recibidos', 'ejemplo.csv', public.archivo_ejemplo_arca('MP', '2026-10', 'recibidos'));
    v := public.resumen_iva_simple('MP', '2026-10');
    r := r || jsonb_build_object('p', 'IVA Simple: después de conciliar, trae las 5 diferencias con ARCA de las compras',
      'ok', (select jsonb_array_length(x->'diferencias') from jsonb_array_elements(v->'conciliaciones') x where x->>'tipo' = 'recibidos') = 5, 'd', v->'conciliaciones');
    r := r || jsonb_build_object('p', 'IVA Simple: la conciliación de otro período no se mezcla',
      'ok', not exists (select 1 from jsonb_array_elements(public.resumen_iva_simple('MP', '2026-11')->'conciliaciones') x where x->>'cuando' is not null), 'd', '');
    raise exception 'DESHACER';
  exception when raise_exception then
    if sqlerrm <> 'DESHACER' then raise; end if;
  end;
  insert into resultado (prueba, ok, detalle) select x->>'p', coalesce((x->>'ok')::boolean, false), x->>'d' from jsonb_array_elements(r) x;
end $$;

-- ---------------------------------------------------------------------
-- 3d. Compras con órdenes de compra (valores de probar-nucleo.js)
-- ---------------------------------------------------------------------
select pg_temp.igual('Bandeja de Mecánica Pesada: 2 órdenes recibidas sin factura',
  jsonb_array_length(public.bandeja_compras('MP')->'ordenes_sin_factura'), 2);
select pg_temp.igual('Deuda sin documentar: 180.000,00 + 40.000,00',
  (public.bandeja_compras('MP')->>'deuda_sin_documentar')::numeric, 220000.00);
select pg_temp.igual('Las facturas de ejemplo tienen orden o categoría', jsonb_array_length(public.bandeja_compras('MP')->'facturas_sin_orden'), 0);
select pg_temp.igual('Órdenes disponibles de Fundición de Prueba: solo la recibida con saldo (EJ-0002-OC 2)',
  (select jsonb_agg(x->>'numero') from jsonb_array_elements(public.ordenes_disponibles('MP', '00000000-0000-0000-0000-0000000000a2')) x), '["EJ-0002-OC 2"]'::jsonb);
select pg_temp.falla('Una orden de la otra empresa no se puede vincular',
  format($$select public.guardar_compra('administracion', '{"empresa_id":"MP","contraparte_id":"00000000-0000-0000-0000-0000000000a1","tipo":1,"punto_venta":9,"numero":7780,
    "fecha":"2026-10-21","desglose":[{"alicuota_codigo":5,"base":"100"}],"ordenes_compra":["%s"]}', false)$$,
    (select id from fiscal.orden_compra where numero = 'EJ-0007-OC 1')), 'EMPRESA_DISTINTA');
select pg_temp.falla('Sin orden ni categoría no se confirma',
  $$select public.guardar_compra('administracion', '{"empresa_id":"MP","contraparte_id":"00000000-0000-0000-0000-0000000000a1","tipo":1,"punto_venta":9,"numero":7779,
    "fecha":"2026-10-21","desglose":[{"alicuota_codigo":5,"base":"100"}],"imagen_path":"MP/x.png"}', true)$$, 'VALIDACION');
select pg_temp.falla('Una categoría que no está en la lista no vale',
  $$select public.guardar_compra('administracion', '{"empresa_id":"MP","contraparte_id":"00000000-0000-0000-0000-0000000000a1","tipo":1,"punto_venta":9,"numero":7779,
    "fecha":"2026-10-21","desglose":[{"alicuota_codigo":5,"base":"100"}],"categoria":"Varios"}', false)$$, 'VALIDACION');
do $$
declare r jsonb := '[]'; v jsonb; v2 jsonb; imp jsonb;
begin
  begin
    -- Al importar de ARCA se sugiere la orden o la categoría
    imp := public.importar_desde_arca('administracion', 'MP', 'recibidos',
      (select jsonb_agg(x->'arca') from jsonb_array_elements(public.conciliar_arca('administracion', 'MP', '2026-10', 'recibidos', 'ejemplo.csv',
        public.archivo_ejemplo_arca('MP', '2026-10', 'recibidos'))->'conciliacion'->'filas') x
       where x->>'estado' = 'falta_sistema' and (x->>'importable')::boolean and (x->'arca'->>'numero')::int in (880, 4567)));
    r := r || jsonb_build_object('p', 'Importada de ARCA: la de Fundición de Prueba se vincula a la orden EJ-0002-OC 2',
      'ok', (select orden_compra from fiscal.comprobante where operacion = 'compra' and numero = 880 and punto_venta = 7) = 'EJ-0002-OC 2', 'd', imp);
    r := r || jsonb_build_object('p', 'Importada de ARCA: la del 27 % lleva la categoría «Luz, gas y agua»',
      'ok', (select categoria_gasto from fiscal.comprobante where operacion = 'compra' and numero = 4567) = 'Luz, gas y agua', 'd', '');
    -- orden de $ 180.000: tolerancia = el menor entre 2 % ($ 3.600) y $ 5.000
    v := public.guardar_compra('administracion', jsonb_build_object('empresa_id', 'MP', 'contraparte_id', '00000000-0000-0000-0000-0000000000a2', 'tipo', 1,
      'punto_venta', 9, 'numero', 7777, 'fecha', '2026-10-21', 'desglose', '[{"alicuota_codigo":5,"base":"190000"}]'::jsonb, 'imagen_path', 'MP/x.png',
      'ordenes_compra', jsonb_build_array((select id from fiscal.orden_compra where numero = 'EJ-0002-OC 2'))), true);
    r := r || jsonb_build_object('p', 'Fuera de tolerancia queda en revisión: diferencia 10.000,00 contra una tolerancia de 3.600,00',
      'ok', (v->'revision_precio'->>'diferencia')::numeric = 10000.00 and (v->'revision_precio'->>'tolerancia')::numeric = 3600.00, 'd', v->'revision_precio');
    v2 := public.guardar_compra('administracion', jsonb_build_object('empresa_id', 'MP', 'contraparte_id', '00000000-0000-0000-0000-0000000000a1', 'tipo', 1,
      'punto_venta', 9, 'numero', 7778, 'fecha', '2026-10-21', 'desglose', '[{"alicuota_codigo":5,"base":"40500"}]'::jsonb, 'imagen_path', 'MP/x.png',
      'ordenes_compra', jsonb_build_array((select id from fiscal.orden_compra where numero = 'EJ-0003-OC 1'))), true);
    r := r || jsonb_build_object('p', 'Dentro de tolerancia no queda en revisión (500,00 contra 800,00)', 'ok', v2->'revision_precio' = 'null'::jsonb, 'd', v2->'revision_precio');
    r := r || jsonb_build_object('p', 'La compra en revisión aparece en la bandeja', 'ok', jsonb_array_length(public.bandeja_compras('MP')->'en_revision') = 1, 'd', '');
    begin
      perform public.aprobar_diferencia('administracion', (v->>'id')::uuid);
      r := r || jsonb_build_object('p', 'Administración no aprueba diferencias', 'ok', false, 'd', 'no falló');
    exception when others then
      r := r || jsonb_build_object('p', 'Administración no aprueba diferencias', 'ok', sqlerrm = 'PROHIBIDO', 'd', sqlerrm);
    end;
    r := r || jsonb_build_object('p', 'El Contador aprueba la diferencia',
      'ok', (public.aprobar_diferencia('contador', (v->>'id')::uuid)->'revision_precio'->>'aprobada_rol') = 'contador', 'd', '');
    raise exception 'DESHACER';
  exception when raise_exception then
    if sqlerrm <> 'DESHACER' then raise; end if;
  end;
  insert into resultado (prueba, ok, detalle) select x->>'p', coalesce((x->>'ok')::boolean, false), x->>'d' from jsonb_array_elements(r) x;
end $$;

-- ---------------------------------------------------------------------
-- 3e. Emitir desde un presupuesto de venta (valores de probar-nucleo.js)
-- ---------------------------------------------------------------------
select pg_temp.igual('Presupuesto en dólares a pesos: 8.000 × 1.545', fiscal.precio_en_pesos(8000, 1545), 12360000.0000);
select pg_temp.igual('Presupuesto en dólares a pesos: 1.200,5 × 1.050,123456', fiscal.precio_en_pesos(1200.5, 1050.123456), 1260673.2089);
select pg_temp.igual('Precio unitario con dos decimales para mostrar', array[fiscal.a_dos_decimales(12360000.0000), fiscal.a_dos_decimales(17.8911), fiscal.a_dos_decimales(0.0050)],
  array[12360000.00, 17.89, 0.01]);
select pg_temp.igual('Siete presupuestos de ejemplo (seis de Mecánica Pesada y uno de Rectificaciones Motores Pesados)',
  jsonb_array_length(public.presupuestos('MP')) * 10 + jsonb_array_length(public.presupuestos('RMP')), 61);
select pg_temp.ok('La línea de EJ-0001 ya está facturada en la Factura A 00001-00000001',
  (select x->'lineas'->0->'facturada'->>'etiqueta' from jsonb_array_elements(public.presupuestos('MP')) x where x->>'numero' = 'EJ-0001') = 'Factura A 00001-00000001');
select pg_temp.igual('Descuento sobre el precio de lista: EJ-0003 (4 × 12.500 con 5 %) da 47.500,00 de neto y 57.475,00 de total',
  (select array[(x->'importes'->>'neto_gravado')::numeric, (x->'importes'->>'total')::numeric] from jsonb_array_elements(public.presupuestos('MP')) x where x->>'numero' = 'EJ-0003'),
  array[47500.00, 57475.00]);
do $$
declare
  r jsonb := '[]';
  p2 jsonb := (select x from jsonb_array_elements(public.presupuestos('MP')) x where x->>'numero' = 'EJ-0002');
  p7 jsonb := (select x from jsonb_array_elements(public.presupuestos('RMP')) x where x->>'numero' = 'EJ-0007');
  v jsonb;
  e text;
begin
  begin
    v := public.guardar_venta('administracion', jsonb_build_object('empresa_id', 'MP', 'punto_venta', 1, 'contraparte_id', p2->'cliente'->>'id', 'fecha', '2026-10-22',
      'presupuesto_id', p2->>'id', 'presupuesto_lineas', jsonb_build_array(p2->'lineas'->0->>'id')), true);
    r := r || jsonb_build_object('p', 'Factura solo la línea tildada de EJ-0002 (2 × 95.000 al 21 %: 229.900,00)',
      'ok', jsonb_array_length(v->'items') = 1 and (v->>'total')::numeric = 229900.00 and v->>'presupuesto' = 'EJ-0002', 'd', v->'items');
    begin
      perform public.guardar_venta('administracion', jsonb_build_object('empresa_id', 'MP', 'punto_venta', 1, 'contraparte_id', p2->'cliente'->>'id', 'fecha', '2026-10-22',
        'presupuesto_id', p2->>'id', 'presupuesto_lineas', jsonb_build_array(p2->'lineas'->0->>'id')), false);
      e := 'no falló';
    exception when others then e := sqlerrm; end;
    r := r || jsonb_build_object('p', 'Una línea del presupuesto se factura una sola vez', 'ok', e = 'LINEA_YA_FACTURADA', 'd', e);
    v := public.guardar_venta('administracion', jsonb_build_object('empresa_id', 'MP', 'punto_venta', 1, 'contraparte_id', p2->'cliente'->>'id', 'fecha', '2026-10-22',
      'presupuesto_id', p2->>'id', 'presupuesto_lineas', jsonb_build_array(p2->'lineas'->1->>'id')), true);
    r := r || jsonb_build_object('p', 'Facturación parcial: la otra línea va en otra factura (60.000 al 10,5 %: 66.300,00)',
      'ok', (v->>'total')::numeric = 66300.00, 'd', v->>'total');
    -- Dólares a pesos
    v := public.guardar_venta('administracion', jsonb_build_object('empresa_id', 'RMP', 'punto_venta', 1, 'contraparte_id', p7->'cliente'->>'id', 'fecha', '2026-10-22',
      'presupuesto_id', p7->>'id', 'presupuesto_lineas', jsonb_build_array(p7->'lineas'->0->>'id'), 'emitir_en', 'pesos', 'cotizacion', '1050'), true);
    r := r || jsonb_build_object('p', 'EJ-0007 en dólares se factura en pesos: 1.200 × 1.050 = 1.260.000,00 de neto, con la equivalencia en la línea',
      'ok', (v->>'neto_gravado')::numeric = 1260000.00 and v->>'moneda' = 'ARS' and v->>'origen_moneda' = 'USD'
            and v->'items'->0->>'descripcion' = E'Rectificación de cigüeñal\nEQUIVALE A DOLARES U$D 1.200 + IVA ($ 1.050)', 'd', v->'items'->0->>'descripcion');
    v := public.guardar_venta('administracion', jsonb_build_object('empresa_id', 'RMP', 'punto_venta', 1, 'contraparte_id', p7->'cliente'->>'id', 'fecha', '2026-10-22',
      'presupuesto_id', p7->>'id', 'presupuesto_lineas', jsonb_build_array(p7->'lineas'->1->>'id'), 'emitir_en', 'dolares', 'cotizacion', '1050'), true);
    r := r || jsonb_build_object('p', 'También se puede emitir en dólares, y el libro lo pasa a pesos con la cotización',
      'ok', v->>'moneda' = 'USD' and (v->>'neto_gravado')::numeric = 800.00
            and (public.libro_iva('RMP', '2026-10', 'venta')->'totales'->>'n21')::numeric = 1260000.00 + 840000.00, 'd', public.libro_iva('RMP', '2026-10', 'venta')->'totales');
    raise exception 'DESHACER';
  exception when raise_exception then
    if sqlerrm <> 'DESHACER' then raise; end if;
  end;
  insert into resultado (prueba, ok, detalle) select x->>'p', coalesce((x->>'ok')::boolean, false), x->>'d' from jsonb_array_elements(r) x;
end $$;
select pg_temp.falla('Un presupuesto cancelado no se factura',
  format($$select public.guardar_venta('administracion', '{"empresa_id":"MP","punto_venta":1,"contraparte_id":"00000000-0000-0000-0000-0000000000c2","fecha":"2026-10-22",
    "presupuesto_id":"%s","presupuesto_lineas":["%s"]}', false)$$, (select id from fiscal.presupuesto where numero = 'EJ-0006'),
    (select l.id from fiscal.presupuesto_linea l join fiscal.presupuesto p on p.id = l.presupuesto_id where p.numero = 'EJ-0006')), 'ESTADO_INVALIDO');
select pg_temp.falla('Sin datos fiscales del cliente no se emite desde el presupuesto',
  format($$select public.guardar_venta('administracion', '{"empresa_id":"MP","punto_venta":1,"contraparte_id":"00000000-0000-0000-0000-0000000000c4","fecha":"2026-10-22",
    "presupuesto_id":"%s","presupuesto_lineas":["%s"]}', true)$$, (select id from fiscal.presupuesto where numero = 'EJ-0004'),
    (select l.id from fiscal.presupuesto_linea l join fiscal.presupuesto p on p.id = l.presupuesto_id where p.numero = 'EJ-0004')), 'DATOS_FISCALES_INCOMPLETOS');
select pg_temp.falla('Sin líneas tildadas no se factura',
  format($$select public.guardar_venta('administracion', '{"empresa_id":"MP","punto_venta":1,"contraparte_id":"00000000-0000-0000-0000-0000000000c2","fecha":"2026-10-22",
    "presupuesto_id":"%s","presupuesto_lineas":[]}', false)$$, (select id from fiscal.presupuesto where numero = 'EJ-0002')), 'VALIDACION');
select pg_temp.falla('Un presupuesto de la otra empresa no se factura',
  format($$select public.guardar_venta('administracion', '{"empresa_id":"MP","punto_venta":1,"contraparte_id":"00000000-0000-0000-0000-0000000000c1","fecha":"2026-10-22",
    "presupuesto_id":"%s","presupuesto_lineas":[]}', false)$$, (select id from fiscal.presupuesto where numero = 'EJ-0007')), 'EMPRESA_DISTINTA');

-- ---------------------------------------------------------------------
-- 3f. Reglas legales, cierre y clientes por prioridad
-- ---------------------------------------------------------------------
do $$
declare r jsonb := '[]'; v jsonb; e text;
begin
  begin
    -- IVA sobre 30,06 = 6,3126 → 6,31; por línea daría 2,10 × 3 = 6,30
    v := public.guardar_venta('administracion', '{"empresa_id":"MP","punto_venta":1,"contraparte_id":"00000000-0000-0000-0000-0000000000c3","fecha":"2026-10-22",
      "lineas":[{"descripcion":"x1","cantidad":"1","precio":"10.02","alicuota_codigo":5},{"descripcion":"x2","cantidad":"1","precio":"10.02","alicuota_codigo":5},
                {"descripcion":"x3","cantidad":"1","precio":"10.02","alicuota_codigo":5}]}', false);
    r := r || jsonb_build_object('p', 'Factura B: líneas con IVA incluido que suman el total (36,37; el centavo va a la última)',
      'ok', (v->>'total')::numeric = 36.37
        and (select array_agg((x->>'unitario')::numeric order by n) from jsonb_array_elements(v->'lineas_iva_incluido') with ordinality q(x, n)) = array[12.12, 12.12, 12.12]
        and (select array_agg((x->>'total')::numeric order by n) from jsonb_array_elements(v->'lineas_iva_incluido') with ordinality q(x, n)) = array[12.12, 12.12, 12.13],
      'd', v->'lineas_iva_incluido');
    -- RG 5866: antes de la vigencia del parámetro no se exige identificar al consumidor final
    v := public.guardar_venta('administracion', '{"empresa_id":"MP","punto_venta":1,"contraparte_id":"00000000-0000-0000-0000-0000000000c3","fecha":"2026-06-30",
      "lineas":[{"descripcion":"Motor","cantidad":"1","precio":"10000000","alicuota_codigo":5}]}', true);
    r := r || jsonb_build_object('p', 'Consumidor final: antes de la vigencia del parámetro (01/07/2026) no hace falta identificarlo',
      'ok', v->>'estado' = 'emitido_sin_cae', 'd', v->>'estado');
    begin
      perform public.guardar_venta('administracion', '{"empresa_id":"MP","punto_venta":1,"contraparte_id":"00000000-0000-0000-0000-0000000000c3","fecha":"2026-10-22",
        "lineas":[{"descripcion":"Motor","cantidad":"1","precio":"10000000","alicuota_codigo":5}]}', true);
      e := 'no falló';
    exception when others then e := sqlerrm; end;
    r := r || jsonb_build_object('p', 'Consumidor final desde $ 10.000.000,00: hay que identificarlo (RG 5866)', 'ok', e = 'DATOS_FISCALES_INCOMPLETOS', 'd', e);
    -- Con la conciliación hecha, el punto queda en orden
    perform public.conciliar_arca('contador', 'MP', '2026-10', 'recibidos', 'ejemplo.csv', public.archivo_ejemplo_arca('MP', '2026-10', 'recibidos'));
    v := public.pendientes_cierre('MP', '2026-10');
    r := r || jsonb_build_object('p', 'Cierre: la conciliación de compras hecha queda en orden y la de ventas sigue pendiente',
      'ok', (select x->>'nivel' from jsonb_array_elements(v->'items') x where x->>'texto' like '%Recibidos%') = 'ok'
        and (select x->>'nivel' from jsonb_array_elements(v->'items') x where x->>'texto' like '%Emitidos%') = 'revisar', 'd', v);
    raise exception 'DESHACER';
  exception when raise_exception then
    if sqlerrm <> 'DESHACER' then raise; end if;
  end;
  insert into resultado (prueba, ok, detalle) select x->>'p', coalesce((x->>'ok')::boolean, false), x->>'d' from jsonb_array_elements(r) x;
end $$;
select pg_temp.igual('Cierre de octubre de Mecánica Pesada: nueve puntos y ninguno bloquea',
  array[jsonb_array_length(public.pendientes_cierre('MP', '2026-10')->'items'), (public.pendientes_cierre('MP', '2026-10')->>'bloquea')::boolean::int], array[9, 0]);
select pg_temp.igual('Cierre: revisar el borrador de venta y las dos conciliaciones con ARCA',
  (public.pendientes_cierre('MP', '2026-10')->>'revisar')::int, 3);
select pg_temp.igual('Cierre: órdenes de compra recibidas sin factura, como información',
  (select x->>'nivel' || ' ' || (x->>'cantidad') from jsonb_array_elements(public.pendientes_cierre('MP', '2026-10')->'items') x where x->>'texto' like 'Órdenes de compra%'), 'info 2');
select pg_temp.igual('Cierre de Rectificaciones Motores Pesados: el presupuesto de venta entregado EJ-0007 tiene líneas sin facturar',
  (select (x->>'cantidad')::int from jsonb_array_elements(public.pendientes_cierre('RMP', '2026-10')->'items') x where x->>'texto' like 'Presupuestos de venta entregados%'), 1);
select pg_temp.igual('Clientes por prioridad (Mecánica Pesada): primero el incompleto, después por monto en presupuestos de venta',
  (select jsonb_agg(x->>'nombre' order by n) from jsonb_array_elements(public.clientes_por_prioridad('MP')) with ordinality q(x, n)),
  '["Sin datos", "Transportes Ejemplo S.A.", "Logística Demo S.R.L.", "Cliente Final de Prueba"]'::jsonb);
select pg_temp.igual('Clientes por prioridad: el monto de Transportes Ejemplo S.A. suma EJ-0001 y EJ-0005 (968.000,00 + 278.300,00)',
  (select (x->>'monto')::numeric from jsonb_array_elements(public.clientes_por_prioridad('MP')) x where x->>'nombre' = 'Transportes Ejemplo S.A.'), 1246300.00);
select pg_temp.igual('Clientes por prioridad, todas las empresas: el presupuesto en dólares se suma en pesos (2.420 × 1.050)',
  (select (x->>'monto')::numeric from jsonb_array_elements(public.clientes_por_prioridad()) x where x->>'nombre' = 'Transportes Ejemplo S.A.'), 1246300.00 + 2541000.00);

-- ---------------------------------------------------------------------
-- 4. Reglas
-- ---------------------------------------------------------------------
select pg_temp.falla('Gerencia no emite facturas',
  $$select public.guardar_venta('gerencia', '{"empresa_id":"MP","punto_venta":1,"contraparte_id":"00000000-0000-0000-0000-0000000000c1","fecha":"2026-10-22",
    "lineas":[{"descripcion":"x","cantidad":"1","precio":"1","alicuota_codigo":5}]}', true)$$, 'PROHIBIDO');
select pg_temp.falla('No se emite a un cliente sin datos fiscales',
  $$select public.guardar_venta('administracion', '{"empresa_id":"MP","punto_venta":1,"contraparte_id":"00000000-0000-0000-0000-0000000000c4","fecha":"2026-10-22",
    "lineas":[{"descripcion":"x","cantidad":"1","precio":"1","alicuota_codigo":5}]}', true)$$, 'DATOS_FISCALES_INCOMPLETOS');
select pg_temp.ok('Pero sí se guarda como borrador',
  (public.guardar_venta('administracion', '{"empresa_id":"MP","punto_venta":1,"contraparte_id":"00000000-0000-0000-0000-0000000000c4","fecha":"2026-10-22",
    "lineas":[{"descripcion":"x","cantidad":"1","precio":"1","alicuota_codigo":5}]}', false)->>'estado') = 'borrador');
select pg_temp.falla('Punto de venta de otra empresa',
  $$select public.guardar_venta('administracion', '{"empresa_id":"RMP","punto_venta":7,"contraparte_id":"00000000-0000-0000-0000-0000000000c1","fecha":"2026-10-22",
    "lineas":[{"descripcion":"x","cantidad":"1","precio":"1","alicuota_codigo":5}]}', true)$$, 'EMPRESA_DISTINTA');
select pg_temp.ok('Consumidor final recibe Factura B',
  (public.guardar_venta('administracion', '{"empresa_id":"MP","punto_venta":1,"contraparte_id":"00000000-0000-0000-0000-0000000000c3","fecha":"2026-10-22",
    "lineas":[{"descripcion":"x","cantidad":"1","precio":"1000","alicuota_codigo":5}]}', true)->>'tipo')::int = 6);
select pg_temp.falla('Consumidor final sin identificar desde $ 10.000.000',
  $$select public.guardar_venta('administracion', '{"empresa_id":"MP","punto_venta":1,"contraparte_id":"00000000-0000-0000-0000-0000000000c3","fecha":"2026-10-22",
    "lineas":[{"descripcion":"x","cantidad":"1","precio":"9000000","alicuota_codigo":5}]}', true)$$, 'DATOS_FISCALES_INCOMPLETOS');

select pg_temp.falla('Una factura emitida no se edita (UPDATE directo)',
  $$update fiscal.comprobante set total = total where operacion = 'venta' and estado = 'emitido_sin_cae'$$, 'COMPROBANTE_INMUTABLE');
select pg_temp.falla('Una factura emitida no se borra (DELETE directo)',
  $$delete from fiscal.comprobante where operacion = 'venta' and estado = 'emitido_sin_cae'$$, 'COMPROBANTE_INMUTABLE');
select pg_temp.falla('El detalle de una emitida no se toca',
  $$update fiscal.comprobante_iva set iva = 0 where comprobante_id in (select id from fiscal.comprobante where estado = 'emitido_sin_cae')$$, 'COMPROBANTE_INMUTABLE');
select pg_temp.falla('Una factura emitida no se edita (RPC)',
  format($$select public.guardar_venta('administracion', '{"id":"%s","empresa_id":"MP","punto_venta":1,"contraparte_id":"00000000-0000-0000-0000-0000000000c1","fecha":"2026-10-05",
    "lineas":[{"descripcion":"x","cantidad":"1","precio":"1","alicuota_codigo":5}]}', false)$$,
    (select id from fiscal.comprobante where operacion = 'venta' and estado = 'emitido_sin_cae' limit 1)), 'COMPROBANTE_INMUTABLE');
select pg_temp.falla('Una emitida no se borra (RPC)',
  format($$select public.eliminar_borrador('administracion', '%s')$$, (select id from fiscal.comprobante where operacion = 'venta' and estado = 'emitido_sin_cae' limit 1)),
  'COMPROBANTE_INMUTABLE');
select pg_temp.falla('El historial no se edita', $$update fiscal.historial set detalle = 'x'$$, 'HISTORIAL_INMUTABLE');

select pg_temp.falla('Las NC no superan el total de la factura',
  format($$select public.emitir_nota_venta('administracion', '{"factura_id":"%s","clase":"credito","fecha":"2026-10-22","motivo":"x","lineas":[{"alicuota_codigo":5,"neto":"200000"}]}')$$,
    (select id from fiscal.comprobante where operacion = 'venta' and tipo = 1 and fecha = '2026-10-12')), 'TOTALES_INCONSISTENTES');
select pg_temp.falla('Toda nota exige un motivo',
  format($$select public.emitir_nota_venta('administracion', '{"factura_id":"%s","clase":"credito","fecha":"2026-10-22","motivo":" ","lineas":[{"alicuota_codigo":5,"neto":"1"}]}')$$,
    (select id from fiscal.comprobante where operacion = 'venta' and tipo = 1 and fecha = '2026-10-12')), 'MOTIVO_OBLIGATORIO');

select pg_temp.falla('Una compra no se carga dos veces',
  $$select public.guardar_compra('administracion', '{"empresa_id":"MP","contraparte_id":"00000000-0000-0000-0000-0000000000a1","tipo":1,"punto_venta":5,"numero":1234,
    "fecha":"2026-10-03","desglose":[{"alicuota_codigo":5,"base":"1"}]}', false)$$, 'NUMERO_DUPLICADO');
select pg_temp.falla('Confirmar exige imagen o CAE',
  $$select public.guardar_compra('administracion', '{"empresa_id":"MP","contraparte_id":"00000000-0000-0000-0000-0000000000a2","tipo":1,"punto_venta":1,"numero":1,
    "fecha":"2026-10-20","desglose":[{"alicuota_codigo":5,"base":"1000"}],"categoria":"Repuestos e insumos"}', true)$$, 'ADJUNTO_OBLIGATORIO');
select pg_temp.ok('Con imagen se confirma',
  (public.guardar_compra('administracion', '{"empresa_id":"MP","contraparte_id":"00000000-0000-0000-0000-0000000000a2","tipo":1,"punto_venta":1,"numero":1,
    "fecha":"2026-10-20","desglose":[{"alicuota_codigo":5,"base":"1000"}],"categoria":"Repuestos e insumos","imagen_path":"MP/prueba.png"}', true)->>'estado') = 'confirmada');
select pg_temp.ok('Con el código de autorización de ARCA se confirma sin imagen (carga a mano desde la conciliación)',
  (public.guardar_compra('administracion', '{"empresa_id":"MP","contraparte_id":"00000000-0000-0000-0000-0000000000a2","tipo":1,"punto_venta":1,"numero":2,
    "fecha":"2026-12-15","desglose":[{"alicuota_codigo":5,"base":"1000"}],"categoria":"Repuestos e insumos","codigo_autorizacion":"FICTICIO-000099"}', true)->>'estado') = 'confirmada');
select pg_temp.falla('Un proveedor sin CUIT no puede tener facturas',
  $$select public.guardar_compra('administracion', '{"empresa_id":"MP","contraparte_id":"00000000-0000-0000-0000-0000000000a4","tipo":1,"punto_venta":1,"numero":1,
    "fecha":"2026-10-20","desglose":[{"alicuota_codigo":5,"base":"1000"}]}', false)$$, 'DATOS_FISCALES_INCOMPLETOS');
select pg_temp.falla('Administración no anula compras (solo Contador)',
  format($$select public.anular_compra('administracion', '%s', 'x')$$, (select id from fiscal.comprobante where operacion = 'compra' and numero = 1 and punto_venta = 1)), 'PROHIBIDO');
select pg_temp.falla('Anular exige motivo',
  format($$select public.anular_compra('contador', '%s', '')$$, (select id from fiscal.comprobante where operacion = 'compra' and numero = 1 and punto_venta = 1)), 'MOTIVO_OBLIGATORIO');
select pg_temp.igual('Crédito con la compra nueva', (public.posicion_iva('MP', '2026-10')->>'credito')::numeric, 107310.00);
select pg_temp.ok('El Contador anula con motivo',
  (public.anular_compra('contador', (select id from fiscal.comprobante where operacion = 'compra' and numero = 1 and punto_venta = 1), 'Cargada por error')->>'estado') = 'anulada');
select pg_temp.igual('La anulada sale del libro', (public.posicion_iva('MP', '2026-10')->>'credito')::numeric, 107100.00);
select pg_temp.ok('Anulada, se puede volver a cargar el mismo número',
  (public.guardar_compra('administracion', '{"empresa_id":"MP","contraparte_id":"00000000-0000-0000-0000-0000000000a2","tipo":1,"punto_venta":1,"numero":1,
    "fecha":"2026-10-20","desglose":[{"alicuota_codigo":5,"base":"1000"}]}', false)->>'estado') = 'borrador');

-- Idempotencia: reintentar con la misma clave no emite dos veces
select pg_temp.igual('Reintento con la misma clave: un solo comprobante',
  (select count(distinct x->>'id')::int from (
     select public.guardar_venta('administracion', '{"empresa_id":"MP","punto_venta":1,"contraparte_id":"00000000-0000-0000-0000-0000000000c2","fecha":"2026-10-22",
       "lineas":[{"descripcion":"x","cantidad":"1","precio":"10","alicuota_codigo":5}]}', true, '11111111-1111-1111-1111-111111111111') x
     from generate_series(1, 2)) r), 1);

-- Cierre de período
select pg_temp.falla('Administración no cierra períodos', $$select public.cerrar_periodo('administracion', 'MP', '2026-10')$$, 'PROHIBIDO');
select pg_temp.ok('El Contador cierra octubre', (public.cerrar_periodo('contador', 'MP', '2026-10')->>'estado') = 'cerrado');
select pg_temp.falla('Período cerrado: no se emite con fecha de octubre',
  $$select public.guardar_venta('administracion', '{"empresa_id":"MP","punto_venta":1,"contraparte_id":"00000000-0000-0000-0000-0000000000c1","fecha":"2026-10-25",
    "lineas":[{"descripcion":"x","cantidad":"1","precio":"1","alicuota_codigo":5}]}', true)$$, 'PERIODO_CERRADO');
select pg_temp.falla('Período cerrado: no se anula una compra de octubre',
  format($$select public.anular_compra('contador', '%s', 'x')$$, (select id from fiscal.comprobante where operacion = 'compra' and numero = 1234)), 'PERIODO_CERRADO');
select pg_temp.falla('Un período cerrado no se vuelve a cerrar', $$select public.cerrar_periodo('contador', 'MP', '2026-10')$$, 'ESTADO_INVALIDO');
select pg_temp.ok('RMP octubre sigue abierto', public.posicion_iva('RMP', '2026-10')->>'estado' = 'abierto');

-- Errores con el status HTTP que entiende PostgREST
select pg_temp.falla('El error lleva SQLSTATE PT409', $$select fiscal.error('PERIODO_CERRADO', 'x')$$, 'PERIODO_CERRADO');
do $$ begin
  perform fiscal.error('PERIODO_CERRADO', 'x');
exception when others then
  perform pg_temp.igual('SQLSTATE de un conflicto', sqlstate, 'PT409');
end $$;

-- Empresas con las que operó cada cliente o proveedor
select pg_temp.igual('Cliente con ventas en MP', (select e->'empresas' from jsonb_array_elements(public.listar_contrapartes('cliente')) e
  where e->>'id' = '00000000-0000-0000-0000-0000000000c2'), '["MP"]'::jsonb);
select pg_temp.igual('Cliente sin comprobantes no tiene empresas', (select e->'empresas' from jsonb_array_elements(public.listar_contrapartes('cliente')) e
  where e->>'id' = '00000000-0000-0000-0000-0000000000c4'), '[]'::jsonb);
select pg_temp.igual('Proveedor con compras en MP', (select e->'empresas' from jsonb_array_elements(public.listar_contrapartes('proveedor')) e
  where e->>'id' = '00000000-0000-0000-0000-0000000000a1'), '["MP"]'::jsonb);

-- El rol anon no ve las tablas
select pg_temp.ok('anon no tiene acceso al esquema fiscal', not has_schema_privilege('anon', 'fiscal', 'usage'));
select pg_temp.ok('anon puede llamar a la API', has_function_privilege('anon', 'public.libro_iva(text, text, text)', 'execute'));

-- ---------------------------------------------------------------------
\o
\pset footer off
select n, case when ok then 'OK ' else 'FALLA' end as r, prueba, case when ok then '' else detalle end as detalle from resultado order by n;
select count(*) filter (where ok) || ' de ' || count(*) || ' pruebas OK' as resumen from resultado;
do $$ begin
  if exists (select 1 from resultado where not ok) then raise exception 'Hay pruebas que fallan'; end if;
end $$;
rollback;
