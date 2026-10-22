# Manual de uso · Facturación e IVA de Motores Pesados

Esta guía explica cómo usar la página paso a paso. Está pensada para alguien que la usa por primera vez y no necesita saber nada técnico.

## Contenido

1. [Para qué sirve](#1-para-qué-sirve)
2. [Conocé la pantalla](#2-conocé-la-pantalla)
3. [Los roles: quién puede hacer qué](#3-los-roles-quién-puede-hacer-qué)
4. [Dar de alta un cliente o un proveedor](#4-dar-de-alta-un-cliente-o-un-proveedor)
5. [Hacer una factura de venta](#5-hacer-una-factura-de-venta)
6. [Corregir una factura de venta: notas de crédito y débito](#6-corregir-una-factura-de-venta-notas-de-crédito-y-débito)
7. [Cargar una factura de compra](#7-cargar-una-factura-de-compra)
8. [Anular una factura de compra](#8-anular-una-factura-de-compra)
9. [Ver los libros de IVA y cuánto hay que pagar](#9-ver-los-libros-de-iva-y-cuánto-hay-que-pagar)
10. [Exportar a Excel](#10-exportar-a-excel)
11. [Cerrar el mes](#11-cerrar-el-mes)
12. [Ver el historial de cambios](#12-ver-el-historial-de-cambios)
13. [Mensajes que te puede mostrar la página](#13-mensajes-que-te-puede-mostrar-la-página)
14. [Preguntas frecuentes](#14-preguntas-frecuentes)
15. [Ejercicio de práctica](#15-ejercicio-de-práctica)
16. [Palabras que conviene conocer](#16-palabras-que-conviene-conocer)

---

## 1. Para qué sirve

La página reúne en un solo lugar todo lo que tiene que ver con las facturas y el IVA de las dos empresas: **Mecánica Pesada** y **Rectificaciones Motores Pesados**. Con ella podés:

- **Hacer facturas de venta** a los clientes y corregirlas si hace falta.
- **Cargar las facturas de compra** que mandan los proveedores, con su foto o PDF.
- **Ver los libros de IVA** de ventas y de compras de cada mes.
- **Saber cuánto IVA hay que pagar** en el mes.
- **Exportar todo a Excel** y **cerrar el mes** cuando está todo controlado.

La página hace las cuentas sola: el IVA, los totales y el número de factura. Vos solo cargás los datos.

---

## 2. Conocé la pantalla

Al entrar vas a ver tres zonas:

**Arriba, una franja de aviso** que dice *AMBIENTE DE PRUEBA*. Te recuerda que nada de lo que hagas tiene validez fiscal.

**A la izquierda, el menú**, con tres grupos:

| Grupo | Opción | Qué encontrás |
|---|---|---|
| Libro de IVA | **Libros y posición** | Los libros del mes y cuánto IVA hay que pagar |
| | **Cierre e historial** | Cerrar el mes y ver todo lo que se hizo |
| Facturas | **Facturas de venta** | Las facturas que hacemos a los clientes |
| | **Facturas de compra** | Las facturas que nos hacen los proveedores |
| Datos | **Clientes** | Los datos de cada cliente para poder facturarle |
| | **Proveedores** | Los datos de cada proveedor |

En el celular, el menú se abre con el botón ☰ que está arriba a la derecha.

**Abajo del menú**, dos cosas:
- **Claro / Oscuro** cambia los colores de la pantalla.
- **Usuario de prueba**, con una lista para elegir el **rol**. El rol define qué podés hacer (ver la sección 3).

**Arriba a la derecha de cada pantalla** aparecen dos botones: **Mecánica Pesada** y **Rectificaciones Motores Pesados**. Con ellos elegís con qué empresa estás trabajando. Las dos empresas nunca se mezclan: cada una tiene sus propias facturas y sus propios libros.

> 💡 Antes de hacer cualquier cosa, fijate que esté elegida la empresa correcta y el rol correcto.

---

## 3. Los roles: quién puede hacer qué

Cada persona de la empresa tiene un rol, y cada rol puede hacer ciertas cosas. En esta versión de prueba no hay usuario ni contraseña: el rol lo elegís vos abajo a la izquierda, para poder probar cómo trabaja cada uno.

| Quiero… | Administración | Contador | Gerencia | Adm. técnico | Estudiante |
|---|:-:|:-:|:-:|:-:|:-:|
| Ver facturas, libros y exportar a Excel | ✓ | ✓ | ✓ | ✓ | ✓ |
| Cargar o corregir datos de clientes y proveedores | ✓ | ✓ | | ✓ | |
| Hacer facturas de venta y notas | ✓ | | | | |
| Cargar facturas de compra | ✓ | ✓ | | | |
| Anular una factura de compra | | ✓ | | | |
| Cerrar el mes | | ✓ | | | |
| Ver el historial de cambios | | ✓ | ✓ | ✓ | ✓ |

Si intentás algo que tu rol no puede hacer, la página te avisa quién sí lo puede hacer. Por ejemplo: *"Tu rol (Gerencia) no puede emitir facturas de venta. Lo hacen: Administración."*

---

## 4. Dar de alta un cliente o un proveedor

Para facturarle a alguien, primero tiene que estar cargado con sus datos fiscales. Lo mismo pasa con un proveedor antes de cargar una compra suya.

**Rol:** Administración, Contador o Administrador técnico.

1. En el menú, entrá a **Clientes** (o **Proveedores**).
2. Vas a ver una tarjeta por cada uno. Las tarjetas con **"Faltan datos fiscales"** en rojo no se pueden usar para facturar hasta completarlas.
   - Los clientes y proveedores son **los mismos para las dos empresas**: un cliente cargado sirve para facturarle desde Mecánica Pesada o desde Rectificaciones Motores Pesados.
   - Cada tarjeta muestra con un punto de color **con qué empresa ya operó** (🟠 Mecánica Pesada, 🔵 Rectificaciones Motores Pesados). Si todavía no tiene comprobantes, dice *"Sin facturas todavía"* (o *"Sin compras todavía"* en proveedores).
   - Arriba, las pestañas **Todas / MP / RMP** filtran la lista por empresa. El número de cada pestaña es cuántos hay.
3. Para uno nuevo, tocá **Nuevo cliente** (o **Nuevo proveedor**). Para completar uno que ya existe, tocá **Completar datos** o **Editar** en su tarjeta.
4. Completá:
   - **Razón social**: el nombre legal.
   - **Nombre en el CRM**: cómo lo conocemos. Si lo dejás vacío, se usa la razón social.
   - **Tipo de documento** y **Número**: el CUIT, sin guiones. En los proveedores siempre es CUIT. Para practicar podés usar un CUIT inventado como `30999999979`.
   - **Condición frente al IVA**: por ejemplo, *Responsable Inscripto* o *Consumidor Final*. Al lado ves qué letra de factura le corresponde.
   - El domicilio, la localidad y el teléfono son opcionales.
5. Tocá **Guardar**.

Si el CUIT está mal escrito, la página te lo marca, porque revisa que el número sea válido.

> 💡 La condición frente al IVA es importante: de ella sale si al cliente se le hace **Factura A** o **Factura B**. No la elegís vos en la factura, la pone la página.

---

## 5. Hacer una factura de venta

**Rol:** Administración.

1. En el menú, entrá a **Facturas de venta** y tocá **Nueva factura de venta**.
2. Arriba completá:
   - **Cliente**: elegilo de la lista. Si no aparece o tiene datos incompletos, primero cargalo (sección 4).
   - **Punto de venta** y **Fecha de emisión**: normalmente ya vienen completos.
   - **Condición de venta**, por ejemplo *Contado* o *Cuenta corriente 30 días*.
   - Opcionales: **Presupuesto de venta**, **Orden de compra del cliente** y **Remito**.
3. Elegí cómo vas a cargar los precios:
   - **Precios sin IVA** es lo normal: cargás el precio de cada cosa y la página le suma el IVA.
   - **Precio final con IVA (mostrador)** sirve para una venta al público donde ya sabés el total que se cobró. Se carga una sola línea.
4. Cargá las líneas, una por cada cosa que vendés:
   - **Código** (opcional) y **Descripción**, por ejemplo *Rectificación de tapa de cilindros*.
   - **Cantidad**, **Precio de lista (sin IVA)** y **Dto. %** si hacés un descuento.
   - **Alícuota**: el porcentaje de IVA. Lo normal es 21 %, y algunos servicios llevan 10,5 %.
   - Para agregar otra línea, tocá **Agregar línea**. Para sacar una, tocá la ✕.
5. Mientras escribís, a la derecha vas a ver cómo se arma la factura: el neto, el IVA de cada alícuota y el **total**.
6. Para terminar tenés dos botones:
   - **Guardar borrador** la guarda para seguir después. Un borrador no tiene número, no cuenta en el libro y se puede cambiar o borrar.
   - **Emitir** hace la factura definitiva. La página le pone el número que sigue, por ejemplo *Factura A 00001-00000005*, y la suma al libro de ventas.

Después de emitir, se abre la factura tal cual sale en papel. Con **Imprimir** la podés imprimir o guardar como PDF.

> ⚠️ **Una factura emitida ya no se puede cambiar ni borrar.** Así lo exige la ley y así funciona la página. Antes de tocar **Emitir**, revisá el cliente, las cantidades y el total. Si te equivocaste, se corrige con una nota (sección 6).

**Para retomar un borrador:** buscalo en **Facturas de venta** (dice *Borrador*), abrilo y tocá **Editar y emitir**. Si no lo vas a usar, tocá **Borrar borrador**.

En la lista de **Facturas de venta** podés filtrar por **Período** (mes) y por **Estado**:
- **Borrador**: todavía no se emitió.
- **Emitida sin CAE**: emitida, pero sin la autorización de ARCA, porque esta versión no se conecta con ARCA.
- **Autorizada**: ya tiene la autorización de ARCA. En esta versión no se usa.

---

## 6. Corregir una factura de venta: notas de crédito y débito

Una factura emitida no se toca. Si hubo un error o un cambio, se hace una **nota** que la corrige:

- **Nota de crédito**: *resta*. Se usa, por ejemplo, si el cliente devolvió algo, si se cobró de más o si hay que anular la factura entera.
- **Nota de débito**: *suma*. Se usa, por ejemplo, si faltó cobrar algo o hay un recargo.

**Rol:** Administración.

1. En **Facturas de venta**, abrí la factura que querés corregir.
2. Tocá **Nota de crédito** o **Nota de débito**.
3. Completá la **Fecha**, el **Motivo** (es obligatorio, por ejemplo *devolución parcial*) y el **Importe sin IVA** por alícuota. La página calcula el IVA y el total de la nota.
4. Tocá **Emitir nota**.

La nota queda asociada a la factura y aparece en el detalle, en **Correcciones**. En el libro de ventas, la nota de crédito aparece con importes en negativo.

> Una nota de crédito no puede ser mayor que lo que queda de la factura. Si la factura era de $ 100.000 y ya hiciste una nota de crédito de $ 30.000, la próxima puede ser como mucho de $ 70.000.

---

## 7. Cargar una factura de compra

Las facturas de compra no se "hacen": las hace el proveedor y nosotros las **cargamos** copiando los datos del papel.

**Rol:** Administración o Contador.

1. En el menú, entrá a **Facturas de compra** y tocá **Cargar factura de compra**.
2. Completá con lo que dice la factura del proveedor:
   - **Proveedor**: elegilo de la lista. Si no está, tocá *¿No está? Agregalo en Proveedores*.
   - **Tipo**: Factura A, B o C, o una nota.
   - **Punto de venta** y **Número**: los del proveedor, por ejemplo `00005` y `00001234`.
   - **Fecha del comprobante**.
   - **Período de IVA**: el mes en que se va a contar en el libro. Normalmente es el de la fecha, y se completa solo.
   - **Vence el pago**, **Orden de compra** y **CAE** son opcionales.
3. Cargá los importes:
   - Si es **Factura A**: en **Importe neto por alícuota** poné la base de cada alícuota (21 %, 10,5 %…). Si tiene más de una, tocá **Agregar alícuota**. La página calcula el IVA.
   - Si es **Factura B o C**: no se discrimina IVA. Cargá todo el importe en **No gravado**.
   - Si la factura trae **No gravado**, **Exento**, **Percepción de IVA**, **Percepción de Ingresos Brutos** u **Otros tributos**, cargalos en su casilla.
4. Revisá que el **Total de la factura** que muestra la página sea igual al del papel del proveedor. Si no coincide, revisá lo que cargaste.
5. En **Imagen o PDF de la factura**, subí la foto o el PDF del comprobante.
6. Para terminar:
   - **Guardar borrador** la guarda sin contarla todavía en el libro.
   - **Confirmar** la cuenta en el libro de compras. Para confirmar hace falta la imagen o el CAE.

> ⚠️ La página no deja cargar dos veces la misma factura del mismo proveedor. Si te aparece *"Esa factura ya está cargada"*, buscala en la lista: seguramente alguien ya la cargó.

> 💡 Solo las **Facturas A** dan *crédito fiscal*, es decir, IVA que se descuenta del que hay que pagar. Las B y las C no.

---

## 8. Anular una factura de compra

Si una compra confirmada estaba mal cargada o no correspondía, no se borra: se **anula**.

**Rol:** Contador.

1. En **Facturas de compra**, abrí la factura.
2. Tocá **Anular**.
3. Escribí el **Motivo**, por ejemplo *cargada dos veces* o *importe mal cargado*. Es obligatorio.
4. Confirmá con **Anular**.

La factura queda en la lista como **Anulada**, con el motivo, y deja de contar en el libro. Si había un error de carga, después podés cargarla de nuevo bien.

---

## 9. Ver los libros de IVA y cuánto hay que pagar

**Rol:** cualquiera.

En el menú, entrá a **Libros y posición**. Arriba vas a ver cuatro recuadros:

- **Débito fiscal**: el IVA de las ventas del mes, lo que cobramos de IVA.
- **Crédito fiscal**: el IVA de las compras del mes, lo que pagamos de IVA.
- **IVA a pagar** (o **Saldo a favor**): débito menos crédito.
- **Estado del período**: *Abierto* si todavía se puede cargar, *Cerrado* si el mes ya se cerró.

Más abajo:
- **Período**: elegí el mes que querés ver.
- Tres pestañas:
  - **Ventas** muestra el libro IVA ventas: una fila por factura emitida, con el neto y el IVA separados por alícuota.
  - **Compras** muestra el libro IVA compras: una fila por factura confirmada.
  - **Posición** muestra la cuenta débito − crédito = a pagar, y las percepciones del mes.
- **Ver todas las columnas** muestra el libro completo, con 27 %, exento, percepciones, etc.
- Tocando el número de un comprobante se abre su detalle.

Qué entra y qué no en los libros:
- Entran las ventas **emitidas** y las compras **confirmadas**.
- **No entran** los borradores ni las compras anuladas.
- Las **notas de crédito restan**, y por eso aparecen en negativo.

---

## 10. Exportar a Excel

1. En **Libros y posición**, elegí la empresa y el **Período**.
2. Tocá **Exportar a Excel**.

Se descarga un archivo con cuatro hojas:
- **Facturas**: todas las facturas del mes, de venta y de compra.
- **Libro IVA Ventas**.
- **Libro IVA Compras**.
- **Posición IVA**.

---

## 11. Cerrar el mes

Cuando el contador terminó de revisar un mes, lo **cierra**. Un mes cerrado queda "congelado": ya no se pueden emitir facturas, cargar compras ni anular con fecha de ese mes.

**Rol:** Contador.

1. En el menú, entrá a **Cierre e historial**.
2. A la izquierda vas a ver los meses con su saldo y si están **Abierto** o **Cerrado**. Tocá el mes que querés cerrar.
3. A la derecha aparece **Antes de cerrar**, con una lista de controles. Cada punto tiene un tilde ✓ si está bien, o un aviso con la cantidad de casos a revisar:
   - facturas de venta que quedaron en borrador;
   - compras que quedaron en borrador;
   - compras confirmadas sin imagen.
4. Revisá esos puntos. Los avisos no impiden cerrar, pero conviene resolverlos. Si algún control **bloquea** el cierre, primero hay que corregirlo.
5. Tocá **Cerrar período** y confirmá.

> ⚠️ En esta versión, un mes cerrado no se puede volver a abrir. Cerralo solo cuando estés seguro.

---

## 12. Ver el historial de cambios

**Rol:** Contador, Gerencia, Administrador técnico o Estudiante.

En **Cierre e historial**, abajo a la derecha, está el **Historial de cambios**. Ahí aparece todo lo que se hizo: quién (qué rol), cuándo, qué hizo y sobre qué comprobante. Por ejemplo: *"Administración · emitió sin CAE factura de venta Factura A 00001-00000005"*.

El historial no se puede editar ni borrar.

---

## 13. Mensajes que te puede mostrar la página

| Si ves… | Quiere decir | Qué hacer |
|---|---|---|
| *Tu rol (…) no puede …* | El rol elegido no tiene permiso para eso | Cambiá el rol abajo a la izquierda al que indica el mensaje |
| *El cliente «…» no tiene datos fiscales completos* | Falta el CUIT, la razón social o la condición de IVA | Completalo en **Clientes** |
| *El CUIT tiene que tener 11 dígitos y un dígito verificador correcto* | El CUIT está mal escrito | Revisá el número |
| *El período … está cerrado* | Ese mes ya se cerró | Usá una fecha de un mes abierto, o consultá con el contador |
| *Esa factura ya está cargada* | La misma compra ya existe | Buscala en **Facturas de compra** |
| *Falta la imagen o el PDF de la factura, o su CAE* | No se puede confirmar una compra sin respaldo | Subí la foto o el PDF |
| *El comprobante ya fue emitido o confirmado y no se puede editar* | Se intentó cambiar algo definitivo | Hacé una nota de crédito o débito, o anulá la compra |
| *Las notas de crédito de una factura no pueden superar su total* | La nota es más grande que lo que queda de la factura | Revisá el importe |
| *Una Factura B/C no discrimina IVA computable…* | Cargaste IVA en una factura B o C | Poné todo el importe en **No gravado** |
| *Desde $ 10.000.000,00 hay que identificar al consumidor final* | Venta grande a un consumidor final sin documento | Cargale CUIT, CUIL o DNI al cliente |

---

## 14. Preguntas frecuentes

**¿Puedo borrar una factura que emití por error?**
No. Hacé una **nota de crédito** por el total de la factura y queda anulada en los números.

**¿Por qué no puedo elegir si la factura es A o B?**
Porque depende del cliente: a un Responsable Inscripto se le hace A, a un Consumidor Final se le hace B. La página lo decide sola según la condición de IVA cargada en **Clientes**.

**¿Por qué mi factura no aparece en el libro?**
Seguramente quedó como **borrador**. Abrila y emitila (venta) o confirmala (compra). También revisá que estés mirando la empresa y el mes correctos.

**¿Qué significa "Emitida sin CAE"?**
Que la factura está hecha, pero no se mandó a ARCA para autorizarla. En esta versión de prueba eso no se hace.

**¿Puedo trabajar con las dos empresas a la vez?**
Sí, pero una por vez: elegí la empresa arriba a la derecha. Cada una tiene sus facturas y sus libros por separado.

**Cambié los datos de un cliente. ¿Cambian las facturas viejas?**
No. Cada factura guarda los datos del cliente tal como estaban el día que se emitió.

**¿Qué pasa si toco "Emitir" dos veces seguidas?**
Nada: la página emite una sola factura.

---

## 15. Ejercicio de práctica

Para aprender, hacé este recorrido con **Mecánica Pesada**:

1. **Mirá el mes de ejemplo.** En **Libros y posición**, elegí *octubre 2026*. Tenés que ver débito fiscal **$ 214.755,37**, crédito fiscal **$ 107.100,00** e IVA a pagar **$ 107.655,37**.
2. **Cargá un cliente.** Con rol *Administración*, en **Clientes → Nuevo cliente**, cargá *Cliente de Práctica S.A.*, CUIT `30999999979`, *Responsable Inscripto*.
3. **Hacé una factura.** En **Facturas de venta → Nueva factura de venta**, elegí ese cliente y cargá una línea: *Servicio de prueba*, cantidad 1, precio 10.000, 21 %. Mirá que el total sea **$ 12.100,00**. Primero tocá **Guardar borrador** y fijate que en el libro todavía no aparece. Después abrila, tocá **Editar y emitir** y **Emitir**.
4. **Corregila.** Abrí la factura emitida y hacé una **Nota de crédito** de 2.000 al 21 %, con el motivo *descuento posterior*. Volvé al libro de ventas y fijate que aparece en negativo.
5. **Cargá una compra.** En **Facturas de compra → Cargar factura de compra**, elegí *Repuestos Ficticios S.A.*, Factura A, punto de venta 5, un número que no exista (por ejemplo 9999), base 5.000 al 21 %. Subí cualquier imagen y tocá **Confirmar**.
6. **Probá los permisos.** Cambiá el rol a *Gerencia* e intentá hacer una factura: la página no te va a dejar. Cambiá a *Contador* y anulá la compra que cargaste, con el motivo *práctica*.
7. **Revisá el historial.** En **Cierre e historial**, fijate que todo lo que hiciste quedó registrado.
8. **Exportá.** En **Libros y posición**, tocá **Exportar a Excel** y abrí el archivo.

> Como lo emitido no se borra, lo que cargues en la práctica va a quedar en la base de prueba. No pasa nada: son datos inventados.

---

## 16. Palabras que conviene conocer

| Palabra | Significa |
|---|---|
| **IVA** | Impuesto al Valor Agregado. Se suma al precio de lo que se vende. |
| **Alícuota** | El porcentaje de IVA: 21 % (lo normal), 10,5 % o 27 %. |
| **Neto** | El importe sin IVA. |
| **Factura A / B / C** | A: entre empresas inscriptas, con el IVA separado. B: a consumidores finales y exentos, con el IVA incluido en el precio. C: la que hacen los monotributistas. |
| **Débito fiscal** | El IVA que cobramos en las ventas. |
| **Crédito fiscal** | El IVA que pagamos en las compras y podemos descontar. |
| **Posición de IVA** | Débito − crédito: lo que hay que pagar en el mes, o lo que queda a favor. |
| **Percepción** | Un impuesto que nos cobra un proveedor por adelantado. Se informa aparte. |
| **Nota de crédito / débito** | Comprobante que corrige una factura, restando o sumando. |
| **Borrador** | Factura guardada pero todavía no emitida o confirmada. No cuenta en los libros. |
| **Período** | Un mes de IVA. |
| **ARCA** | El organismo de impuestos (ex AFIP). |
| **CAE** | El código con el que ARCA autoriza una factura electrónica. |
| **CUIT** | El número de identificación fiscal de una empresa o persona. |

---

*La explicación técnica de cómo está hecho el sistema, para desarrolladores, está en [docs/tecnico.md](docs/tecnico.md).*
