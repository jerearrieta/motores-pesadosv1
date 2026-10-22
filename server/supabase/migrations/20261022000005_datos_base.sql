-- =====================================================================
-- Las dos empresas y sus puntos de venta. Datos inventados: los CUIT
-- son de prueba (válidos por dígito verificador, no pertenecen a nadie).
-- =====================================================================

insert into fiscal.empresa (id, razon_social, nombre_corto, cuit, condicion_iva, domicilio, telefono, ingresos_brutos, inicio_actividades, leyenda) values
  ('MP', 'Mecánica Pesada (ficticia) S.A.', 'Mecánica Pesada', '30999999901', 1, 'Calle Falsa 123, Córdoba (ficticio)', '0351-000-0000', '900-000001-0', '2010-01-01',
   'Después de pasados los 7 días del vencimiento, se aplicará un 10% de interés mensual sobre el total de la factura.'),
  ('RMP', 'Rectificaciones Motores Pesados (ficticia) S.A.', 'Rectificaciones Motores Pesados', '30999999804', 1, 'Avenida Inventada 456, Córdoba (ficticio)', '0351-000-0001', '900-000002-0', '2012-03-01',
   'Después de pasados los 7 días del vencimiento, se aplicará un 10% de interés mensual sobre el total de la factura.');

insert into fiscal.punto_venta (empresa_id, numero, descripcion) values
  ('MP', 1, 'Punto de venta de prueba'),
  ('RMP', 1, 'Punto de venta de prueba');
