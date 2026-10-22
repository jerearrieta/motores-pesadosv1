# Motores Pesados · Prototipo 1.0

Módulo de facturación e IVA para el CRM de Motores Pesados (Mecánica Pesada y Rectificaciones Motores Pesados): carga de facturas de venta y de compra, **dos libros de IVA separados** (ventas y compras), **posición de IVA** y **cierre de período**.

Unifica los dos frontends del equipo: la base es el *Simulador Libro de IVA* (cálculo en centavos, alícuotas, notas de crédito y débito, cierre, roles), toma del repo *motores-pesados-contable* el contrato de API (todo por RPC, el front nunca arma un número ni un importe para guardar) y del Excel `prototipo-libro-iva.xlsx` las columnas de los libros y de la exportación.

> **Ambiente de prueba.** Todos los datos son inventados y los comprobantes no tienen validez fiscal. No se pide CAE a ARCA.

## Estructura

```
client/   App Next.js (pantallas). Habla con el server solo por supabase.rpc().
server/   Supabase: migraciones SQL (tablas, cálculo, reglas y API), pruebas.
```

| Carpeta | Qué hay |
|---|---|
| `server/supabase/migrations/…01_esquema_fiscal.sql` | Tablas en el esquema `fiscal` (no expuesto por la API) |
| `…02_reglas_y_calculo.sql` | Catálogos de ARCA, cálculo fiscal, inmutabilidad, permisos por rol |
| `…03_api.sql` | Funciones RPC que usa el client (libros, posición, guardar venta/compra, notas, anular, cerrar) |
| `…04_storage.sql` | Bucket `comprobantes` para imágenes y PDF de las facturas de compra |
| `…05_datos_base.sql` | Las dos empresas y sus puntos de venta (ficticios) |
| `…06_datos_ejemplo.sql` | Facturas de ejemplo del Simulador (se pueden sacar) |
| `server/tests/` | 73 pruebas: cálculo, libros contra la verdad de referencia, reglas |
| `client/app/` | Pantallas: Libros y posición, Cierre e historial, Ventas, Compras, Clientes, Proveedores |

## Cómo se calcula

El cálculo vive **una sola vez, en el server** (`fiscal.calcular_venta` y `fiscal.calcular_compra`). Mientras se carga una factura, el client pide una vista previa con `calcular_comprobante` (no guarda nada); al guardar, el server vuelve a calcular y valida.

- Importes `numeric(14,2)`, nunca float. Redondeo: mitad hacia arriba.
- Línea: precio unitario = lista × (100 − descuento) ÷ 100; importe = cantidad × precio unitario.
- IVA por alícuota **sobre la suma de netos** (no línea por línea).
- Total = neto gravado + no gravado + exento + IVA + otros tributos + percepciones.
- Posición = débito fiscal − crédito fiscal. Las percepciones se informan aparte.
- Las notas de crédito restan en el libro. Las compras B y C no dan crédito fiscal.

## Reglas que hace cumplir la base

1. La empresa va en todo comprobante; MP y RMP nunca se mezclan en el libro.
2. Lo emitido o confirmado **no se edita ni se borra** (trigger): se corrige con nota de crédito o débito, o se anula una compra con motivo.
3. La numeración de ventas la pone la base al emitir, sin huecos (numerador con `FOR UPDATE`).
4. La letra sale de la condición de IVA del cliente (A para responsables inscriptos, B para consumidor final y exentos).
5. Una compra no se carga dos veces; para confirmarla hace falta imagen o CAE.
6. Un período cerrado bloquea emitir, cargar y anular con fecha de ese mes.
7. Todo deja historial, que es de solo altas.
8. Permisos por rol (sin login en esta versión: el rol se elige en la pantalla).

## Puesta en marcha

### 1. Supabase

Opción A, con la integración de GitHub (recomendada): en el proyecto de Supabase, **Project Settings → Integrations → GitHub**, elegir este repo, **Working directory = `server`** y activar **Deploy to production**. Cada merge a `main` aplica las migraciones nuevas.

Opción B, a mano: ejecutar los archivos de `server/supabase/migrations/` en orden en el **SQL Editor**.

### 2. Client local

```bash
cd client
cp .env.example .env.local    # completar URL y anon key (Project Settings → API)
npm install
npm run dev                   # http://localhost:3000
```

### 3. Vercel

Importar el repo con **Root Directory = `client`** y cargar las variables `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_ANON_KEY`.

### Pruebas del server

```bash
server/tests/correr.sh    # necesita un Postgres local; crea una base temporal
```

Verifican, entre otras cosas, que octubre de 2026 de MP dé débito 214.755,37, crédito 107.100,00 y saldo a pagar 107.655,37 (la verdad de referencia del Simulador).

## Fuera de esta versión

Login real (Supabase Auth con los roles en el token), pedido de CAE a ARCA, presupuestos y órdenes de compra del CRM, conciliación con «Mis Comprobantes», moneda extranjera en pantalla, libro diario y asientos.
