-- =====================================================================
-- Datos de ejemplo para la demostración (los mismos del Simulador
-- Libro de IVA). Todo inventado. Se cargan con las mismas funciones
-- que usa el front, así que también prueban las reglas.
-- Octubre 2026 de MP tiene que dar: débito 214.755,37, crédito
-- 107.100,00, saldo a pagar 107.655,37 (server/tests/pruebas.sql).
-- =====================================================================

insert into fiscal.contraparte (id, codigo, nombre, es_cliente, es_proveedor, tipo_doc, numero_doc, razon_social, condicion_iva, domicilio, localidad, provincia, telefono) values
  ('00000000-0000-0000-0000-0000000000c1', '00101', 'Transportes Ejemplo S.A.', true, false, 80, '30999999928', 'Transportes Ejemplo S.A.', 1, 'Dirección ficticia 1', 'Villa Ficticia', 'Córdoba', '0351-000-0101'),
  ('00000000-0000-0000-0000-0000000000c2', '00102', 'Logística Demo S.R.L.', true, false, 80, '30999999936', 'Logística Demo S.R.L.', 1, 'Dirección ficticia 2', 'Ciudad Demo', 'Santa Fe', '0342-000-0102'),
  ('00000000-0000-0000-0000-0000000000c3', '00103', 'Cliente Final de Prueba', true, false, 99, '0', 'Consumidor Final', 5, '', '', '', ''),
  ('00000000-0000-0000-0000-0000000000c4', '00104', 'Sin datos', true, false, null, null, null, null, '', '', '', ''),
  ('00000000-0000-0000-0000-0000000000a1', 'P001', 'Repuestos Ficticios S.A.', false, true, 80, '33999999943', 'Repuestos Ficticios S.A.', 1, '', '', '', ''),
  ('00000000-0000-0000-0000-0000000000a2', 'P002', 'Fundición de Prueba S.R.L.', false, true, 80, '30999999952', 'Fundición de Prueba S.R.L.', 1, '', '', '', ''),
  ('00000000-0000-0000-0000-0000000000a3', 'P003', 'Taller Muestra', false, true, 80, '27999999986', 'Taller Muestra', 6, '', '', '', ''),
  ('00000000-0000-0000-0000-0000000000a4', 'P004', 'Otros prov. locales', false, true, null, null, null, null, '', '', '', '');

do $$
declare
  r text := 'administracion';
  v2 jsonb;
  c1 jsonb;
begin
  -- Ventas de MP
  perform public.guardar_venta(r, '{"empresa_id":"MP","punto_venta":1,"contraparte_id":"00000000-0000-0000-0000-0000000000c1","fecha":"2026-10-05",
    "condicion_venta":"Cuenta corriente 30 días","presupuesto":"EJ-0001",
    "lineas":[{"codigo":"CONJ-001","descripcion":"Conjunto armado","cantidad":"1","precio":"800000","alicuota_codigo":5}]}', true);
  v2 := public.guardar_venta(r, '{"empresa_id":"MP","punto_venta":1,"contraparte_id":"00000000-0000-0000-0000-0000000000c2","fecha":"2026-10-12",
    "condicion_venta":"Cuenta corriente 30 días",
    "lineas":[{"descripcion":"Repuestos","cantidad":"1","precio":"150000","alicuota_codigo":5},
              {"descripcion":"Mano de obra","cantidad":"1","precio":"40000","alicuota_codigo":4}]}', true);
  perform public.guardar_venta(r, '{"empresa_id":"MP","punto_venta":1,"contraparte_id":"00000000-0000-0000-0000-0000000000c3","fecha":"2026-10-15",
    "modo":"precio_final","condicion_venta":"Contado",
    "lineas":[{"descripcion":"Venta de mostrador","total":"100000","alicuota_codigo":5}]}', true);
  perform public.emitir_nota_venta(r, jsonb_build_object('factura_id', v2->>'id', 'clase', 'credito', 'fecha', '2026-10-20',
    'motivo', 'Devolución parcial de repuestos', 'lineas', '[{"alicuota_codigo":5,"neto":"30000"}]'::jsonb));
  perform public.guardar_venta(r, '{"empresa_id":"MP","punto_venta":1,"contraparte_id":"00000000-0000-0000-0000-0000000000c1","fecha":"2026-11-03",
    "condicion_venta":"Contado",
    "lineas":[{"descripcion":"Servicio de rectificación","cantidad":"1","precio":"100000","alicuota_codigo":5}]}', true);
  -- Un borrador, para mostrar que no entra al libro
  perform public.guardar_venta(r, '{"empresa_id":"MP","punto_venta":1,"contraparte_id":"00000000-0000-0000-0000-0000000000c1","fecha":"2026-10-21",
    "condicion_venta":"A convenir","presupuesto":"EJ-0005",
    "lineas":[{"codigo":"TUR-REA","descripcion":"Turbo reacondicionado","cantidad":"1","precio":"230000","alicuota_codigo":5}]}', false);

  -- Compras de MP (con CAE de ejemplo como respaldo)
  c1 := public.guardar_compra(r, '{"empresa_id":"MP","contraparte_id":"00000000-0000-0000-0000-0000000000a1","tipo":1,"punto_venta":5,"numero":1234,
    "fecha":"2026-10-03","vencimiento_pago":"2026-11-02","desglose":[{"alicuota_codigo":5,"base":"500000"}],"percepcion_iibb":"7500",
    "cae":"70000000000001","orden_compra":"EJ-0001-OC 1"}', true);
  perform public.guardar_compra(r, '{"empresa_id":"MP","contraparte_id":"00000000-0000-0000-0000-0000000000a1","tipo":1,"punto_venta":5,"numero":1250,
    "fecha":"2026-10-08","vencimiento_pago":"2026-11-07","desglose":[{"alicuota_codigo":4,"base":"120000"}],"no_gravado":"3000",
    "cae":"70000000000002","orden_compra":"EJ-0002-OC 1"}', true);
  perform public.guardar_compra(r, '{"empresa_id":"MP","contraparte_id":"00000000-0000-0000-0000-0000000000a3","tipo":11,"punto_venta":2,"numero":50,
    "fecha":"2026-10-10","vencimiento_pago":"2026-10-10","no_gravado":"48000","cae":"70000000000003"}', true);
  perform public.guardar_compra(r, jsonb_build_object('empresa_id', 'MP', 'contraparte_id', '00000000-0000-0000-0000-0000000000a1', 'tipo', 3,
    'punto_venta', 5, 'numero', 77, 'fecha', '2026-10-18', 'desglose', '[{"alicuota_codigo":5,"base":"50000"}]'::jsonb,
    'asociado_id', c1->>'id', 'motivo', 'Devolución de mercadería', 'cae', '70000000000004'), true);
  perform public.guardar_compra(r, '{"empresa_id":"MP","contraparte_id":"00000000-0000-0000-0000-0000000000a2","tipo":1,"punto_venta":7,"numero":900,
    "fecha":"2026-11-05","vencimiento_pago":"2026-12-05","desglose":[{"alicuota_codigo":5,"base":"200000"}],"cae":"70000000000005","orden_compra":"EJ-0001-OC 2"}', true);
end $$;
