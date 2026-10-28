# Un RIF por negocio (Grupo Azullab)

Revisado el 28-10-2026. Esto no sustituye al contador del cliente. Todo lo marcado *confirmar con el contador* depende de cómo esté constituida cada empresa.

## La idea en una frase

La farmacia, el laboratorio y el CrossFit son **tres contribuyentes distintos**, cada uno con su propio RIF. Cada uno factura, numera, lleva sus libros, declara y retiene por su cuenta. El dueño puede ver los tres juntos en su tablero, pero **ese consolidado es solo para gerencia y no es un documento fiscal**. Nada fiscal se mezcla entre RIF.

| Negocio | Razón social (muestra) | RIF (muestra) | IVA de lo que vende |
| --- | --- | --- | --- |
| Laboratorio | Grupo Empresarial Azullab, C.A. | J-50134578-3 | Servicios médico-asistenciales: exentos |
| Farmacia | Azullab Farmacia, C.A. | J-XXXXXXXX-1 | Medicinas exentas; cuidado personal y otros productos al 16 % |
| CrossFit | Fitness Lab Evolution, C.A. | J-XXXXXXXX-2 | Mensualidades, clases y productos al 16 % |

Los RIF son de muestra: **se confirman con el cliente**. El del laboratorio es el que ya usa el grupo, pero hay que confirmar que el laboratorio factura con ese RIF y no con uno propio.

## Qué normas aplican

- **Hasta el 18-04-2027:** Providencia 0071 (facturación). Pide máquina fiscal a quien vende productos farmacéuticos al consumidor final. El laboratorio y el box no están obligados, pero la máquina fiscal es un medio válido para todos.
- **Normas técnicas de la máquina:** Providencia SNAT/2018/0141 (G.O. 41.518).
- **Desde el 19-04-2027:** Providencia SNAT/2026/00093 (G.O. 43.484 del 21-10-2026). Cada contribuyente elige su medio de emisión; la forma libre queda prohibida.
- **Medio que usa Cuadre en los tres negocios:** **impresora fiscal homologada**, una por RIF, con su número de registro, Reporte X, Reporte Z diario y talonario de imprenta autorizada solo si la impresora falla. Detalle en `07 - Impresora fiscal y tasa BCV.md`.
  - Farmacia: HKA80, registro `Z7C0012345` (muestra), en la Caja 1.
  - Laboratorio: HKA80, registro `Z7C0012346` (muestra), en Atención.
  - CrossFit: HKA80, registro `Z7C0012347` (muestra), en la recepción del box.

  El código fiscal es el mismo en los tres. El medio se escoge en `FX_SYS.medio`: `'maquina'` para la impresora fiscal. Sigue disponible `'digital'` para la imprenta digital, por si algún negocio se cambia después del 19-04-2027.
- **Base de los tres:** contribuyente ordinario. Contribuyente especial (IGTF y retenciones de IVA) es un módulo apagado.

## Qué exige el SENIAT a cada RIF y qué hace Cuadre

### 1. Datos del emisor

| Exigencia | Qué hace Cuadre |
| --- | --- |
| Razón social, RIF y domicilio fiscal en cada documento | **Configuración → Datos fiscales** (solo el dueño): razón social, RIF, domicilio fiscal, teléfono, tipo de contribuyente, impresora fiscal (marca, modelo, número de registro y servicio técnico autorizado), talonario para fallas y contador. El RIF queda además grabado en la memoria fiscal de cada impresora. Facturas, notas, libros, cierres y reportes toman los datos de ahí y de ningún otro lugar. |

### 2. La factura (0071; 0141; 00093, art. 8)

| Exigencia | Qué hace Cuadre |
| --- | --- |
| La palabra FACTURA | Sí, en la factura completa y en el ticket de 80 mm. |
| Numeración consecutiva y única | Una serie por RIF. La farmacia, el laboratorio y el box empiezan cada uno en su propio 00000001. |
| Factura impresa por la máquina fiscal, numerada en su memoria fiscal | El número lo da la impresora. La factura de máquina **no lleva número de control** (ese es de la imprenta); lleva el número de registro de la máquina. Solo las del talonario, cuando la impresora falla, llevan número de control preimpreso. |
| Fecha y hora, con a. m. o p. m. | Sí. |
| Cliente con nombre y RIF, o cédula para la persona natural que no necesita factura con RIF | Sí. Sin datos sale "Consumidor final". |
| Por renglón: descripción, cantidad, precio unitario y monto; lo exento marcado (E) | Sí. |
| Monto exento, base imponible por alícuota, IVA por alícuota y total | Sí: subtotal exento, base 16 %, IVA 16 % (y 8 % si hubiera) y total en Bs. |
| Operación en moneda extranjera: total en divisas y su equivalente en bolívares con el tipo de cambio (art. 8, num. 12) | Si se cobra en dólares (efectivo o Zelle), la factura muestra lo pagado en dólares, su equivalente en Bs y la tasa BCV del día. |
| Identificación de la máquina fiscal | "SENIAT" arriba del ticket y, al pie, el logotipo fiscal **MH** con el número de registro. |

Revisado en cada sistema:

- **Farmacia:** pasó de imprenta digital a impresora fiscal (la 0071 la pide a quien vende medicinas). Tiene domicilio, teléfono, equivalencia en divisas y la copia de la factura en pantalla.
- **Laboratorio:** el RIF y la dirección salen de Datos fiscales. Todos los servicios van exentos (E). La factura la imprime su propia impresora fiscal en Atención.
- **CrossFit:** **no facturaba**: daba recibos internos sin IVA. Ahora cada mensualidad, clase o producto sale con factura de su impresora fiscal y **IVA de 16 %**. El precio del plan es la base y la factura le suma el impuesto (por ejemplo, el plan mensual ilimitado de $35 se factura en $40,60).

### 3. Notas de crédito y de débito (0071; 00093, arts. 12 y 13)

| Exigencia | Qué hace Cuadre |
| --- | --- |
| Una factura emitida no se borra ni se edita | No hay botón para editar ni borrar. Se corrige con una nota. |
| La nota sale por el mismo medio que la factura y lleva "Nota de Crédito" o "Nota de Débito" | La imprime la misma impresora fiscal, con su propio número consecutivo. Resta o suma en el Reporte Z del día. |
| La nota cita la factura: número, fecha, monto y el registro de la máquina que la emitió (o el número de control, si era del talonario) | Sí, en la nota y en el Libro de Ventas (columna "Factura afectada"). |
| Las notas van al Libro de Ventas | La de crédito resta y la de débito suma. |

Casos de la maqueta, en **Facturas y notas**:

- **Farmacia, devolución:** nota de crédito por lo devuelto. El producto vuelve al inventario, a su lote, y sale como devolución en el registro del art. 177.
- **Laboratorio, anulación de una orden:** botón "Anular", que emite una nota de crédito por el total. La orden queda anulada y sale de la lista de trabajo.
- **CrossFit, reembolso de una mensualidad:** nota de crédito por el total. La fecha de vencimiento del socio vuelve a la que tenía.
- Nota de débito en los tres: por ejemplo, un cargo de entrega o un ajuste de precio.

Sin internet las notas salen igual, porque la impresora va por cable. Si la impresora está en falla, la nota espera a que la reparen. *Confirmar con el contador si en la falla se emite la nota en un formato del talonario.*

### 4. Libros y reportes (uno por RIF, en **Libros y declaración**)

| Libro | Base | Qué hace Cuadre |
| --- | --- | --- |
| Libro de Ventas | Reglamento de la Ley del IVA, arts. 70 a 72 y 76 a 78 | Facturas con RIF una por una; consumidor final en un renglón por día con su **Reporte Z**, del primer al último número y el registro de la máquina (art. 77); facturas del talonario, si la impresora falló, una por una con su número de control; notas de crédito restando y de débito sumando. Resumen del mes por alícuota (art. 72). |
| Libro de Compras | Mismo reglamento, arts. 70 a 75 | Proveedor, RIF, factura, número de control, exento, gravado y crédito fiscal. Las notas de crédito de proveedores restan. |
| Retenciones de ISLR | Decreto 1.808 | Lista de lo retenido al pagar alquiler, honorarios y servicios, con su comprobante, si se entregó y si se enteró. |
| Borrador de la forma 30 | Ley del IVA | Débitos menos créditos, menos el excedente del mes anterior y las retenciones recibidas: monto a pagar o excedente para el mes siguiente. **Lo revisa el contador; no se presenta desde el sistema.** |
| Registro de inventario (solo farmacia) | Reglamento de la Ley de ISLR, art. 177 | Entradas, devoluciones de clientes, salidas, retiros y existencia valorada a costo promedio. |
| Calendario fiscal | — | En el tablero del dueño y en Libros: cierre de libros, retenciones de ISLR, relación mensual y IVA, con **fechas de muestra** según el último dígito del RIF. |

El resumen del Libro de Ventas **cuadra con el borrador de la forma 30**: la pantalla lo comprueba y lo dice ("Coincide con la forma 30").

**Exportar a Excel:** cada libro se descarga como archivo CSV (se abre en Excel) con las mismas columnas de las plantillas `Libro de Ventas IVA.xlsx`, `Libro de Compras IVA.xlsx` y `Registro de Inventario.xlsx`, más el encabezado con la razón social, el RIF y el período.

### 5. Reporte Z, falla de la impresora y Libro de Control (0141; 0071)

| Exigencia | Qué hace Cuadre |
| --- | --- |
| Reporte Z (reporte global diario) por cada día de operación | Botón "Reporte Z", una sola vez por día; si se repite, el sistema avisa a qué hora y quién lo hizo. El Reporte X muestra lo vendido sin cerrar. |
| Libro de Control de Reparación y Mantenimiento en el local | El libro físico va junto a cada máquina; el sistema guarda una copia (instalación, inspecciones, reparaciones). |
| Solo el servicio técnico autorizado repara la máquina y cambia el precinto | Al marcar la falla, el sistema pide avisar al servicio técnico y anota la reparación al volver. |
| Mientras la máquina está dañada, se factura con formatos de imprenta autorizada con número de control | La caja pide el número preimpreso del talonario y registra la factura. Va una por una en el Libro de Ventas y no suma en el Reporte Z. |

Funciona igual en los tres: botón "Simular falla de la impresora" (en Facturas y notas), venta, e "Impresora reparada". **Sin internet no hace falta el talonario:** la impresora sigue facturando.

### 6. Grupo Azullab (tablero del dueño)

- El dueño ve en su tablero los tres negocios juntos: ventas e IVA del mes de cada uno, con su razón social y su RIF.
- Aviso fijo: **"Cada negocio factura, declara y lleva sus libros con su propio RIF. Este consolidado no es un documento fiscal."**
- El IVA de un negocio no se suma ni se compensa con el de otro. Cada sistema solo tiene en sus libros los documentos de su RIF.

### 7. Checklist del SENIAT (pantalla nueva en cada sistema)

RIF exhibido · impresora fiscal homologada y registrada · Reporte Z de cada día · Libro de Control de Reparación y Mantenimiento · talonario para fallas en el local · libros en el establecimiento · declaraciones del mes al día · retenciones enteradas · contador asignado. Lo que depende de datos de muestra queda en "Revisar" hasta que se confirme.

## Qué hay que confirmar con el contador

1. **IVA de cada negocio:**
   - farmacia: qué productos van exentos (medicinas, art. 18 de la Ley del IVA) y cuáles al 16 %; en especial suplementos y vitaminas;
   - laboratorio: que la exención de servicios médico-asistenciales (Ley del IVA, art. 19) le aplica, y qué hacer con el IVA de sus compras, que no se puede descontar si todo lo que vende es exento;
   - CrossFit: que mensualidades, clases y productos van al 16 %, y si el precio que se anuncia es con o sin IVA.
2. **Prorrata del crédito fiscal** (Ley del IVA, art. 34) en la farmacia, que vende exento y gravado.
3. **Formato del Libro de Ventas con impresora fiscal:** renglón por Reporte Z para el consumidor final y cómo se tratan las facturas con cédula y con RIF que también suman en el Z.
4. **Talonario para fallas de la impresora:** si lleva serie y numeración propias, y qué número de control preimpreso trae.
5. **Numeración de las notas:** la impresora lleva un contador para las notas de crédito; confirmar con el modelo escogido si emite notas de débito.
6. **Fechas del calendario fiscal** de un contribuyente ordinario para el IVA y para enterar las retenciones de ISLR. Las de la maqueta son de muestra.
7. **Retenciones de ISLR:** plazo para enterar, formato del comprobante y de la relación mensual (XML), y si cada arrendador o proveedor es persona natural o empresa.
8. **Registro del art. 177 en sistema:** llevarlo en un medio electrónico requiere autorización del SENIAT.
9. **Una impresora fiscal por RIF:** modelo, número de registro, distribuidor autorizado en Mérida y fecha de instalación de cada una. Si dos negocios comparten local, cada uno necesita su propia máquina con su RIF. Ver el documento 07.
10. **Excedente de crédito del mes anterior** de cada negocio: los montos de la maqueta son de muestra.

## Preguntas para el cliente

1. **¿Cuántos RIF son?** ¿La farmacia, el laboratorio y el CrossFit son tres empresas con su RIF, o alguno factura con el RIF de otro? ¿Grupo Empresarial Azullab, C.A. es el laboratorio o la casa matriz?
2. **¿Es el mismo local o son locales distintos?** Cada establecimiento debe tener su RIF a la vista, su talonario y sus libros. Si comparten local, hay que separar bien cajas, talonarios y libros.
3. **¿Alguno es contribuyente especial?** Revisarlo en el portal del SENIAT después del 01-11-2026 (depuración del padrón). Si lo es, se activa el módulo de IGTF y retenciones de IVA solo en ese RIF.
4. **¿Quién es el contador?** ¿Es el mismo para los tres? ¿Cómo quiere recibir los libros (Excel, PDF) y cada cuánto?
5. Razón social, RIF y domicilio fiscal exactos de cada uno, como salen en el RIF.
6. ¿Ya tienen impresoras fiscales? ¿De qué modelo y con qué distribuidor? ¿Tienen talonarios de imprenta autorizada para cuando falle la máquina?

## Fuentes

- [Providencia SNAT/2026/00093: medios de emisión, requisitos de la factura, notas, número de control y contingencia (resumen del articulado)](https://docs.cachicamo.app/fiscal/providencia00093-emision-facturas-2026)
- [Finanzas Digital: el SENIAT levanta el uso obligatorio de máquinas fiscales (Gaceta Oficial 43.484)](https://finanzasdigital.com/seniat-levanta-uso-obligatorio-maquinas-fiscales-gaceta-oficial/)
- [Boletín de Grant Thornton sobre la PA 00093](https://www.grantthornton.com.ve/globalassets/1.-member-firms/venezuela/2026/boletin-informativo-pa-00093-facturacion.pdf)
- [Providencia 0071 (facturación vigente hasta el 18-04-2027)](https://www.mileoconsultores.com/wp-content/uploads/2015/02/PA00071_2011.pdf)
- [Reglamento General de la Ley del IVA, Decreto 206 (libros de compras y ventas)](https://pandectasdigital.blogspot.com/2016/09/reglamento-general-de-la-ley-que.html)
- [Art. 177 del Reglamento de la Ley de ISLR](https://tugacetaoficial.com/tributario/?p=908)
- [Código Orgánico Tributario, art. 102 (sanciones por libros)](https://www.ley.com.ve/tributario/codigo-organico-tributario-articulo-102)
- [Tabla de retenciones de ISLR, Decreto 1.808 (Forvis Mazars)](https://www.forvismazars.com/ve/es/insights/forvis-mazars-insights/tabla-de-retenciones-islr-ut-9-00-bs-may-2023)
- Documentos de esta carpeta: `00` (guía general), `01` (sin internet), `02` (imprenta digital, estudio previo), `03` (retenciones) y `07` (impresora fiscal y tasa BCV).
