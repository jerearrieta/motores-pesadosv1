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
    "fecha":"2026-10-20","desglose":[{"alicuota_codigo":5,"base":"1000"}]}', true)$$, 'ADJUNTO_OBLIGATORIO');
select pg_temp.ok('Con imagen se confirma',
  (public.guardar_compra('administracion', '{"empresa_id":"MP","contraparte_id":"00000000-0000-0000-0000-0000000000a2","tipo":1,"punto_venta":1,"numero":1,
    "fecha":"2026-10-20","desglose":[{"alicuota_codigo":5,"base":"1000"}],"imagen_path":"MP/prueba.png"}', true)->>'estado') = 'confirmada');
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
