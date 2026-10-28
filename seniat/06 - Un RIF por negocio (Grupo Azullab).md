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

- **Hasta el 18-04-2027:** Providencia 0071 (facturación). Pide máquina fiscal a quien vende productos farmacéuticos al consumidor final. Por eso la farmacia factura con impresora fiscal: ver `07 - Farmacia con impresora fiscal y tasa BCV.md`.
- **Desde el 19-04-2027:** Providencia SNAT/2026/00093 (G.O. 43.484 del 21-10-2026). Cada contribuyente elige su medio de emisión; la forma libre queda prohibida.
- **Medio que usa Cuadre en cada negocio:**
  - **farmacia:** impresora fiscal homologada (Providencia SNAT/2018/0141), con Reporte X, Reporte Z diario y talonario de imprenta autorizada solo si la impresora falla;
  - **laboratorio y CrossFit:** imprenta digital autorizada, con talonario de contingencia.
  
  El código fiscal es el mismo en los tres; el medio se escoge en `FX_SYS.medio` (`'maquina'` o `'digital'`).
- **Base de los tres:** contribuyente ordinario. Contribuyente especial (IGTF y retenciones de IVA) es un módulo apagado.

## Qué exige el SENIAT a cada RIF y qué hace Cuadre

### 1. Datos del emisor

| Exigencia | Qué hace Cuadre |
| --- | --- |
| Razón social, RIF y domicilio fiscal en cada documento | **Configuración → Datos fiscales** (solo el dueño): razón social, RIF, domicilio fiscal, teléfono, tipo de contribuyente, imprenta digital (nombre y RIF), serie del número de control, providencia de autorización, talonario y contador. Facturas, notas, libros, cierres y reportes toman los datos de ahí y de ningún otro lugar. |

### 2. La factura (00093, art. 8; 0071)

| Exigencia | Qué hace Cuadre |
| --- | --- |
| La palabra FACTURA | Sí, en la factura completa y en el ticket de 80 mm. |
| Numeración consecutiva y única | Una serie por RIF. La farmacia, el laboratorio y el box empiezan cada uno en su propio 00000001. |
| Número de control con 2 dígitos de serie y hasta 8 de correlativo, asignado por la imprenta (arts. 9 y 42) | Simulado: `00-00001251`. Lo "asigna" la imprenta en el momento de emitir. |
| Fecha y hora, con a. m. o p. m. | Sí. |
| Cliente con nombre y RIF, o cédula para la persona natural que no necesita factura con RIF | Sí. Sin datos sale "Consumidor final". |
| Por renglón: descripción, cantidad, precio unitario y monto; lo exento marcado (E) | Sí. |
| Monto exento, base imponible por alícuota, IVA por alícuota y total | Sí: subtotal exento, base 16 %, IVA 16 % (y 8 % si hubiera) y total en Bs. |
| Operación en moneda extranjera: total en divisas y su equivalente en bolívares con el tipo de cambio (art. 8, num. 12) | Si se cobra en dólares (efectivo o Zelle), la factura muestra lo pagado en dólares, su equivalente en Bs y la tasa BCV del día. |
| Datos de la imprenta digital y verificación | Leyenda con el nombre y el RIF de la imprenta y el número de la providencia, más el código QR de verificación (de muestra). |

Revisado en cada sistema:

- **Farmacia:** ya facturaba por imprenta digital. Se completaron el domicilio, el teléfono, la leyenda de la imprenta con su RIF y providencia, la equivalencia en divisas y la factura completa en pantalla.
- **Laboratorio:** el RIF y la dirección estaban escritos a mano dentro del ticket. Ahora salen de Datos fiscales. Todos los servicios van exentos (E).
- **CrossFit:** **no facturaba**: daba recibos internos sin IVA. Ahora cada mensualidad, clase o producto sale con factura y **IVA de 16 %**. El precio del plan es la base y la factura le suma el impuesto (por ejemplo, el plan mensual ilimitado de $35 se factura en $40,60).

### 3. Notas de crédito y de débito (00093, arts. 12 y 13)

| Exigencia | Qué hace Cuadre |
| --- | --- |
| Una factura emitida no se borra ni se edita | No hay botón para editar ni borrar. Se corrige con una nota. |
| La nota sale por el mismo medio que la factura y lleva "Nota de Crédito" o "Nota de Débito" | Sale por la imprenta digital, con su propio número consecutivo y su número de control. |
| La nota cita la factura: número, número de control, fecha y monto | Sí, en la nota y en el Libro de Ventas (columna "Factura afectada"). |
| Las notas van al Libro de Ventas | La de crédito resta y la de débito suma. |

Casos de la maqueta, en **Facturas y notas**:

- **Farmacia, devolución:** nota de crédito por lo devuelto. El producto vuelve al inventario, a su lote, y sale como devolución en el registro del art. 177.
- **Laboratorio, anulación de una orden:** botón "Anular", que emite una nota de crédito por el total. La orden queda anulada y sale de la lista de trabajo.
- **CrossFit, reembolso de una mensualidad:** nota de crédito por el total. La fecha de vencimiento del socio vuelve a la que tenía.
- Nota de débito en los tres: por ejemplo, un cargo de entrega o un ajuste de precio.

Sin internet, las notas esperan a que vuelva la conexión, porque las emite la imprenta. *Confirmar con la imprenta si su API permite anular una factura el mismo día sin nota.*

### 4. Libros y reportes (uno por RIF, en **Libros y declaración**)

| Libro | Base | Qué hace Cuadre |
| --- | --- | --- |
| Libro de Ventas | Reglamento de la Ley del IVA, arts. 70 a 72 y 76 a 78 | Facturas con RIF una por una; consumidor final agrupado por día, del primer al último número y número de control; facturas de contingencia con su número de talonario; notas de crédito restando y de débito sumando. Resumen del mes por alícuota (art. 72). |
| Libro de Compras | Mismo reglamento, arts. 70 a 75 | Proveedor, RIF, factura, número de control, exento, gravado y crédito fiscal. Las notas de crédito de proveedores restan. |
| Retenciones de ISLR | Decreto 1.808 | Lista de lo retenido al pagar alquiler, honorarios y servicios, con su comprobante, si se entregó y si se enteró. |
| Borrador de la forma 30 | Ley del IVA | Débitos menos créditos, menos el excedente del mes anterior y las retenciones recibidas: monto a pagar o excedente para el mes siguiente. **Lo revisa el contador; no se presenta desde el sistema.** |
| Registro de inventario (solo farmacia) | Reglamento de la Ley de ISLR, art. 177 | Entradas, devoluciones de clientes, salidas, retiros y existencia valorada a costo promedio. |
| Calendario fiscal | — | En el tablero del dueño y en Libros: cierre de libros, retenciones de ISLR, relación mensual y IVA, con **fechas de muestra** según el último dígito del RIF. |

El resumen del Libro de Ventas **cuadra con el borrador de la forma 30**: la pantalla lo comprueba y lo dice ("Coincide con la forma 30").

**Exportar a Excel:** cada libro se descarga como archivo CSV (se abre en Excel) con las mismas columnas de las plantillas `Libro de Ventas IVA.xlsx`, `Libro de Compras IVA.xlsx` y `Registro de Inventario.xlsx`, más el encabezado con la razón social, el RIF y el período.

### 5. Contingencia (00093, arts. 6, 7 y 11) · laboratorio y CrossFit

La farmacia no usa esto: su contingencia es la falla de la impresora fiscal (ver el documento 07).

| Exigencia | Qué hace Cuadre |
| --- | --- |
| Talonario de imprenta autorizada solo para contingencias (apagón, caída del internet, falla del equipo), y en el local (art. 6) | Cuando no hay internet, la caja pide el número del talonario y registra la factura con ese número. |
| Al terminar la contingencia, registrar las facturas en papel y enviarlas en PDF a la imprenta al día siguiente (art. 7) | Al volver la conexión, Cuadre marca esas facturas como reportadas en PDF a la imprenta. También hay un botón "Reportar en PDF a la imprenta". |
| Número de control preimpreso; la copia dice "sin derecho a crédito fiscal" (art. 11) | El ticket y la factura de contingencia lo dicen. |

Funciona igual en los tres: botón "Simular corte de internet", venta, y "Volver a tener internet". En el CrossFit el botón está arriba, en la barra del dueño.

### 6. Grupo Azullab (tablero del dueño)

- El dueño ve en su tablero los tres negocios juntos: ventas e IVA del mes de cada uno, con su razón social y su RIF.
- Aviso fijo: **"Cada negocio factura, declara y lleva sus libros con su propio RIF. Este consolidado no es un documento fiscal."**
- El IVA de un negocio no se suma ni se compensa con el de otro. Cada sistema solo tiene en sus libros los documentos de su RIF.

### 7. Checklist del SENIAT (pantalla nueva en cada sistema)

RIF exhibido · providencia de la imprenta · talonario de contingencia en el local · libros en el establecimiento · declaraciones del mes al día · retenciones enteradas · contador asignado. Si hay facturas de contingencia por reportar, aparece también ese punto. Lo que depende de datos de muestra queda en "Revisar" hasta que se confirme.

## Qué hay que confirmar con el contador

1. **IVA de cada negocio:**
   - farmacia: qué productos van exentos (medicinas, art. 18 de la Ley del IVA) y cuáles al 16 %; en especial suplementos y vitaminas;
   - laboratorio: que la exención de servicios médico-asistenciales (Ley del IVA, art. 19) le aplica, y qué hacer con el IVA de sus compras, que no se puede descontar si todo lo que vende es exento;
   - CrossFit: que mensualidades, clases y productos van al 16 %, y si el precio que se anuncia es con o sin IVA.
2. **Prorrata del crédito fiscal** (Ley del IVA, art. 34) en la farmacia, que vende exento y gravado.
3. **Formato del Libro de Ventas con imprenta digital:** si el consumidor final se agrupa por día y cómo se tratan las facturas con cédula.
4. **Talonario de contingencia:** si lleva serie y numeración propias, y qué número de control preimpreso trae.
5. **Numeración de las notas:** si las notas de crédito y de débito llevan cada una su serie (como en la maqueta) o comparten la de las facturas.
6. **Fechas del calendario fiscal** de un contribuyente ordinario para el IVA y para enterar las retenciones de ISLR. Las de la maqueta son de muestra.
7. **Retenciones de ISLR:** plazo para enterar, formato del comprobante y de la relación mensual (XML), y si cada arrendador o proveedor es persona natural o empresa.
8. **Registro del art. 177 en sistema:** llevarlo en un medio electrónico requiere autorización del SENIAT.
9. **Farmacia con impresora fiscal:** modelo, número de registro, distribuidor autorizado en Mérida y fecha de instalación. Laboratorio y CrossFit: paso a imprenta digital antes del 19-04-2027. Ver los documentos 02 y 07.
10. **Excedente de crédito del mes anterior** de cada negocio: los montos de la maqueta son de muestra.

## Preguntas para el cliente

1. **¿Cuántos RIF son?** ¿La farmacia, el laboratorio y el CrossFit son tres empresas con su RIF, o alguno factura con el RIF de otro? ¿Grupo Empresarial Azullab, C.A. es el laboratorio o la casa matriz?
2. **¿Es el mismo local o son locales distintos?** Cada establecimiento debe tener su RIF a la vista, su talonario y sus libros. Si comparten local, hay que separar bien cajas, talonarios y libros.
3. **¿Alguno es contribuyente especial?** Revisarlo en el portal del SENIAT después del 01-11-2026 (depuración del padrón). Si lo es, se activa el módulo de IGTF y retenciones de IVA solo en ese RIF.
4. **¿Quién es el contador?** ¿Es el mismo para los tres? ¿Cómo quiere recibir los libros (Excel, PDF) y cada cuánto?
5. Razón social, RIF y domicilio fiscal exactos de cada uno, como salen en el RIF.
6. ¿Ya hay imprenta digital escogida? ¿Con qué providencia está autorizada? ¿Tienen talonarios de contingencia?

## Fuentes

- [Providencia SNAT/2026/00093: medios de emisión, requisitos de la factura, notas, número de control y contingencia (resumen del articulado)](https://docs.cachicamo.app/fiscal/providencia00093-emision-facturas-2026)
- [Finanzas Digital: el SENIAT levanta el uso obligatorio de máquinas fiscales (Gaceta Oficial 43.484)](https://finanzasdigital.com/seniat-levanta-uso-obligatorio-maquinas-fiscales-gaceta-oficial/)
- [Boletín de Grant Thornton sobre la PA 00093](https://www.grantthornton.com.ve/globalassets/1.-member-firms/venezuela/2026/boletin-informativo-pa-00093-facturacion.pdf)
- [Providencia 0071 (facturación vigente hasta el 18-04-2027)](https://www.mileoconsultores.com/wp-content/uploads/2015/02/PA00071_2011.pdf)
- [Reglamento General de la Ley del IVA, Decreto 206 (libros de compras y ventas)](https://pandectasdigital.blogspot.com/2016/09/reglamento-general-de-la-ley-que.html)
- [Art. 177 del Reglamento de la Ley de ISLR](https://tugacetaoficial.com/tributario/?p=908)
- [Código Orgánico Tributario, art. 102 (sanciones por libros)](https://www.ley.com.ve/tributario/codigo-organico-tributario-articulo-102)
- [Tabla de retenciones de ISLR, Decreto 1.808 (Forvis Mazars)](https://www.forvismazars.com/ve/es/insights/forvis-mazars-insights/tabla-de-retenciones-islr-ut-9-00-bs-may-2023)
- Documentos de esta carpeta: `00` (guía general), `01` (sin internet), `02` (imprenta digital) y `03` (retenciones).
