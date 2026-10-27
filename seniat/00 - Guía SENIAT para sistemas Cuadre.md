# Guía SENIAT para sistemas Cuadre

Esta guía explica qué exige el SENIAT a un comercio como Azullab Farmacia y cómo lo resuelve el sistema. Es la base contable de todos los sistemas Cuadre. **No sustituye al contador del cliente**: cada punto marcado con *Confirmar con el contador* depende de la situación de la empresa.

Revisada el 27-10-2026. Las normas cambian; revisa la sección de fuentes antes de cada propuesta.

> **Cambio grande en facturación (21-10-2026):** la máquina fiscal deja de ser obligatoria, con la Providencia SNAT/2026/00093, vigente desde el 19-04-2027. La homologación de software fue derogada en agosto de 2026. Todo lo de facturación está en **`02 - Facturación sin máquina fiscal (imprenta digital).md`**. El punto 7 de esta guía ya está actualizado.
>
> **Base de Cuadre: contribuyente ordinario.** IGTF, retenciones de IVA y demás obligaciones de contribuyente especial van en un **módulo aparte**. Las retenciones de ISLR sí van en la base, porque las hace toda empresa.

---

## 1. Lo esencial en una tabla

| Libro o registro | Quién lo exige | Cada cuánto | Lo genera Cuadre |
| --- | --- | --- | --- |
| Libro de Compras (IVA) | Reglamento de la Ley del IVA, arts. 70 a 75 | Cada compra, en orden y sin atraso; cierre mensual | Sí, desde Compras |
| Libro de Ventas (IVA) | Reglamento de la Ley del IVA, arts. 70 a 72 y 76 a 78 | Cada factura (o Reporte Z), en orden; cierre mensual | Sí, desde las facturas digitales (o los Reportes Z con el módulo de máquina fiscal) |
| Registro de entradas y salidas de inventario | Reglamento de la Ley de ISLR, art. 177 | Mensual, por unidades y valores | Sí, desde los movimientos de inventario |
| Libro de Inventarios | Código de Comercio, arts. 32 y 35 | Al comenzar el negocio y al cierre de cada año | El sistema entrega los datos; el contador lo pasa al libro sellado |
| Libro Diario y Libro Mayor | Código de Comercio, art. 32 | Contabilidad continua | No en la fase 1: es trabajo del contador. Cuadre le exporta los datos |

Plantillas en Excel de los tres primeros, en esta misma carpeta:

- `Libro de Compras IVA.xlsx`
- `Libro de Ventas IVA.xlsx` (contribuyentes, Reporte Z y resumen)
- `Registro de Inventario.xlsx` (art. 177 y el inventario anual del Código de Comercio)

Escribe solo en azul; el IVA, los totales, el costo promedio y el resumen se calculan solos.

---

## 2. Libro de Compras

**Base:** Reglamento General de la Ley del IVA (Decreto 206, G.O. 5.363 Extraordinario del 12-07-1999), arts. 70 a 75.

Reglas:

- Se registra **en orden cronológico y sin atrasos** (art. 70), con las facturas, notas de débito y notas de crédito, nacionales o de importación.
- Se queda **en el establecimiento** (art. 71). Si llega un fiscal y el libro está en la oficina del contador, es una falta.
- Al final de cada mes lleva un **resumen**: bases, créditos fiscales y compras exentas, agrupadas por alícuota. Ese resumen **debe coincidir con la declaración** (art. 72).
- Se puede llevar en sistema, pero se conservan los archivos y los soportes hasta que prescriba la obligación (art. 73).

Datos de cada registro (art. 75):

1. Fecha y número del documento (factura, nota de débito o de crédito, o declaración de aduana en importaciones).
2. Nombre o razón social del proveedor.
3. RIF del proveedor.
4. Montos separados: gravado (por alícuota), exento, exonerado, no sujeto o sin derecho a crédito, y el **crédito fiscal** de lo gravado.

En la práctica, y en la plantilla, se agregan: **número de control** de la factura, tipo de documento, factura afectada (en notas), total con IVA y, solo si la farmacia es agente de retención, el IVA retenido y el número del comprobante.

> **En una farmacia, casi todas las compras son exentas:** los medicamentos están exentos de IVA (Ley del IVA, art. 18). Lo gravado son el cuidado personal, los pañales, los servicios (internet, alquiler) y los equipos. *Confirmar con el contador la clasificación de los suplementos y vitaminas.*

---

## 3. Libro de Ventas

**Base:** mismo reglamento, arts. 70 a 72 y 76 a 78.

Hay **dos tipos de registro**, y el art. 78 exige llevarlos separados:

**a) Ventas a contribuyentes (art. 76).** Son las facturas con el RIF del cliente, una por una:

- Fecha y número de la factura, nota de débito o nota de crédito.
- Nombre o razón social y RIF del cliente.
- Montos gravados por alícuota, exentos, exonerados y no sujetos, con el **débito fiscal**.

**b) Ventas a consumidor final por máquina fiscal (art. 77, Parágrafo Segundo).** Se anota el **reporte global diario (Reporte Z)** de cada máquina, con:

- Fecha, número del Reporte Z y **número de registro (serial) de la máquina fiscal**.
- Primera y última factura del día.
- Total gravado del día, su IVA y el total exento.

Si hay varias máquinas fiscales, se lleva **una línea por máquina** (art. 77, Parágrafo Primero).

**c) Con imprenta digital (lo que usará Azullab):**

- Cada factura tiene su número de control.
- Las facturas con RIF se anotan una por una.
- Las de consumidor final se anotan por día, del primer al último número de control, igual que pide el art. 77 para los comprobantes.
- Las facturas de contingencia (talonario) se anotan con su número.

*Confirmar el formato con el contador.*

> **Cómo evitar contar dos veces:** las facturas con RIF también salen por la máquina fiscal y suman en su Reporte Z. La práctica es listarlas una por una en "contribuyentes" y anotar en la línea del Reporte Z solo el resto del día. Cuadre lo hace solo. *Confirmar el criterio con el contador de Azullab.*

**Resumen mensual (art. 72):** bases, débitos fiscales y ventas exentas por alícuota. Debe coincidir con la declaración de IVA (forma 30).

**Si la farmacia vende por internet:** la Providencia SNAT/2024/000102 (arts. 5 y 6) exige que las ventas hechas por medios electrónicos o portales web se facturen por **medios digitales** y se registren en el Libro de Ventas **separadas** de las de la máquina fiscal. Ver el punto 7.

---

## 4. Registro de inventario (art. 177 del Reglamento de ISLR)

Es el registro que el SENIAT pide en las fiscalizaciones y que más falta en los comercios.

- Se lleva **en el domicilio fiscal o el establecimiento**.
- Es **mensual**, con **entradas y salidas de mercancía por unidades y por valores**, e incluye los **retiros y el autoconsumo**.
- Se puede llevar a mano o en hojas impresas **foliadas y encuadernadas**. Llevarlo en un medio electrónico requiere autorización del SENIAT.
- En la práctica se valora a **costo promedio**. El total de entradas debe cuadrar con la cuenta de compras y el de salidas con el costo de ventas.
- Las pérdidas o faltantes sin explicar pueden tratarse como retiros gravados con IVA (Ley del IVA, art. 3). Por eso Cuadre registra los vencidos y las devoluciones a droguería como movimientos con motivo.

Columnas de la plantilla: código, producto, unidad, inventario inicial (cantidad, costo y total), entradas, costo promedio del mes, salidas, retiros y autoconsumo, e inventario final. Trae una comprobación que debe dar cero.

> **Por qué esto es clave para el diseño del sistema:** en Cuadre el inventario no es un número que se edita. Es la **suma de movimientos** (compra, venta, devolución, vencido, ajuste), cada uno con su lote, fecha, usuario y costo. Así el registro del art. 177 sale solo y, de paso, las ventas sin internet nunca chocan al sincronizar (ver la guía del modo sin conexión).

---

## 5. Libro de Inventarios (Código de Comercio)

- Art. 32: todo comerciante lleva Diario, Mayor e Inventarios.
- Art. 35: **al comenzar el negocio y al fin de cada año**, se hace en el libro de Inventarios una descripción estimatoria de todos los bienes (muebles e inmuebles), créditos, activos y pasivos. Se cierra con el **balance** y la **cuenta de ganancias y pérdidas**.
- Son libros que se presentan en el Registro Mercantil antes de usarlos (art. 33) y los lleva el contador.

Cuadre entrega lo que el contador necesita para ese inventario anual: existencia valorada al 31-12, cuentas por pagar a droguerías y ventas del año. La hoja **"Inventario anual (C. Comercio)"** de la plantilla trae la estructura.

---

## 6. IVA, IGTF y retenciones en una farmacia

| Tema | Regla | En Cuadre |
| --- | --- | --- |
| Medicamentos | Exentos de IVA (Ley del IVA, art. 18) | Marca (E) por producto |
| Cuidado personal, pañales, cosméticos | Alícuota general **16 %** | Marca (G) |
| Alícuota reducida 8 % | Solo para los bienes que la ley señala: carnes, aves, ganado y productos agropecuarios básicos. En una farmacia casi nunca aplica | Opción (R) en el producto. Los libros de ventas y compras traen sus columnas (base y débito o crédito al 8 %) aunque queden en cero |
| **IGTF 3 % por pagos en divisas** | Lo **cobran (perciben) solo los Sujetos Pasivos Especiales** (contribuyentes especiales) designados por la Providencia SNAT/2022/000013 (G.O. 42.339, 17-03-2022). Deben reflejarlo en la factura. | **Módulo contribuyente especial.** No viene en la base. Revisado el 27-10-2026: a diciembre de 2025 los agentes de percepción siguen siendo solo los especiales y los bancos; no hay providencia nueva. Al cobrar en dólares, la caja le explica al cajero por qué no se cobra. *Confirmar con el contador.* |
| Retenciones de IVA como agente | Las practican los contribuyentes especiales a sus proveedores (Providencia SNAT/2025/000054) | **Módulo contribuyente especial** |
| Retenciones de ISLR como agente | **Toda empresa** que paga alquiler, honorarios, servicios, fletes o publicidad (Decreto 1.808), sea especial u ordinaria | **Viene en la base** (corregido el 27-10-2026) |
| IVA que le retienen a Azullab | Si un cliente de Azullab es especial y le retiene IVA, el comprobante se anota en el Libro de Ventas | Viene en la base: es solo una columna |

El detalle, con ejemplos en bolívares, está en `03 - Retenciones SENIAT.md`.

> **Corrección para la maqueta:** la versión anterior cobraba IGTF en toda venta en dólares. Una farmacia que no es contribuyente especial **no** debe cobrarlo. Ya quedó como opción en el Módulo fiscal.

---

## 7. Facturación: qué puede y qué no puede hacer Cuadre

**Actualizado el 27-10-2026.** El detalle, los costos y la conexión están en `02 - Facturación sin máquina fiscal (imprenta digital).md`.

1. **Hasta el 18-04-2027** rigen las normas viejas: la Providencia 0071, que pide máquina fiscal a quien vende productos farmacéuticos, la 0141 y la 102. Pero **no se están vendiendo máquinas nuevas** desde julio de 2026, y el Ejecutivo anunció que suspendía la obligación. Para una farmacia nueva, el camino prudente es que su contador **pida autorización para imprenta digital** y use un **talonario autorizado** mientras tanto. *Confirmarlo con el contador y el SENIAT de Mérida.*
2. **Desde el 19-04-2027** (Providencia **SNAT/2026/00093**): cada comercio **elige** entre imprenta digital o proveedor autorizado, el portal o la app gratuita del SENIAT, o máquina fiscal. La forma libre queda prohibida; el papel solo para contingencias, reportado en PDF al día siguiente.
3. **La homologación de software se derogó** el 12-08-2026 (Providencia SNAT/2026/00084 deroga la 000121). Cuadre no necesita homologarse, porque **la validez fiscal la da la imprenta digital** que asigna el número de control.
4. **Cuadre nunca emite una factura "fiscal" por su cuenta** (un PDF propio no vale). Siempre la emite la **imprenta digital** por API, o la **máquina fiscal** si el cliente ya tiene una (módulo).
5. **Ventas por internet (tienda web de la fase 2):** con imprenta digital da igual que la venta sea en el mostrador o en línea; el mismo conector factura las dos.
6. **Notas de entrega a clientes** (órdenes de entrega): el régimen de medios digitales cubre las órdenes de entrega y las guías de despacho, así que salen **por la imprenta digital**, con número de control y la leyenda "sin derecho a crédito fiscal". Después se emite la factura, que menciona la nota. *Confirmar el formato con el contador y la imprenta.*
7. Lo que Cuadre genera por su cuenta: **traslados internos** entre sedes, **control interno**, los **libros**, el **cierre del día** y los **reportes** para el contador.

## 8. Multas si no se llevan bien (Código Orgánico Tributario, art. 102)

| Falta | Sanción |
| --- | --- |
| No llevar los libros y registros exigidos, o alterar o no conservar la memoria de las máquinas fiscales | Cierre de 10 días continuos y multa de **150 veces** el tipo de cambio oficial de la moneda de mayor valor publicado por el BCV |
| Libros fuera del establecimiento o no presentados al fiscal; atraso de más de un mes; sin las formalidades; no conservar los registros o sistemas; contabilidad fuera del castellano o de la moneda nacional | Cierre de 5 días y multa de **100 veces** ese tipo de cambio |

El cierre aplica a todas las sucursales y dura hasta que se corrija la falta. **Este es el argumento de venta:** con Cuadre los libros están al día y en la farmacia, todos los días.

---

## 9. Qué le preguntamos al cliente (o a su contador) antes de configurar

1. ¿Es **contribuyente especial**? Revisarlo en el portal del SENIAT, porque el padrón cambia el 01-11-2026. Si lo es, se instala el módulo de contribuyente especial.
2. Su **RIF**, razón social y domicilio fiscal exactos, como aparecen en el registro.
3. ¿Tiene ya **máquina fiscal**? Lo normal en una farmacia nueva es que no. Si no la tiene, ¿su contador ya pidió **autorización para imprenta digital**? ¿Con cuál imprenta?
4. ¿Va a **cobrar ventas por internet** o solo tomar pedidos?
5. ¿Quién es su **contador** y en qué formato quiere recibir los libros (Excel, PDF)?
6. Fecha de inicio de operaciones, para el **inventario inicial** del Código de Comercio.

---

## Fuentes

- [Reglamento General de la Ley del IVA, Decreto 206 (texto)](https://pandectasdigital.blogspot.com/2016/09/reglamento-general-de-la-ley-que.html)
- [Art. 177 del Reglamento de la Ley de ISLR](https://tugacetaoficial.com/tributario/?p=908)
- [Registro de entradas y salidas de inventario, art. 177 (Omar Giménez, CPC)](https://omargimenezcpc.blogspot.com/2026/06/registro-entradas-salidas-inventario-venezuela.html)
- [Código de Comercio, art. 35: inventario al inicio y al fin](https://www.ley.com.ve/comercio/codigo-comercio-articulo-35-inventario-inicio-y-fin)
- [Código Orgánico Tributario, art. 102](https://www.ley.com.ve/tributario/codigo-organico-tributario-articulo-102)
- [Providencias SNAT/2024/000102 y 000121 (Gálac)](https://galac.com/galac-blog/providencias-seniat-facturacion/)
- [Aspectos relevantes de la facturación digital (LEĜA Abogados)](https://lega.law/perspectivas-lega/aspectos-relevantes-pa-facturacion-digital/)
- [Texto de la Providencia SNAT/2024/000102](https://tugacetaoficial.com/leyes/texto-providencia-seniat-utilizacion-de-medios-digitales-para-emision-de-facturas-y-otros-documentos-17-12-2025/)
- [Libro de ventas con máquina fiscal y facturas digitales](https://e-learningvzla.com.ve/libro-de-ventas-maquina-fiscal-y-facturas-digitales/)
- [IGTF: Sujetos Pasivos Especiales como agentes de percepción (PwC)](https://www.pwc.com/ve/es/publicaciones/assets/PublicacionesNew/Boletines/Providencia%20Administrativa%20IGTF%20Agentes%20de%20Percepci%C3%B3n.pdf)
- [SENIAT designa agentes de percepción del IGTF (Gerencia y Tributos)](https://gerenciaytributos.blogspot.com/2022/03/seniat-designa-agentes-percepcion-IGTF-divisas.html)
- [Guía básica de los libros fiscales del IVA (LS Tributos)](https://www.lstributos.com/2025/10/guia-libros-IVA.html)
- [Providencia SNAT/2026/00093 (resumen del articulado)](https://docs.cachicamo.app/fiscal/providencia00093-emision-facturas-2026)
- [Derogatoria de la homologación de sistemas (Forvis Mazars)](https://www.forvismazars.com/ve/es/insights/forvis-mazars-insights/fmi-0726-derogatoria-de-sistemas-homologados)
- [Exención de medicamentos, art. 18 de la Ley del IVA (texto de reforma)](https://alertas-v3.directoriolegislativo.org/wp-content/uploads/2020/01/VEN.-Reforma-Ley-IVA-29-01-20.pdf)
- [IGTF: agentes de percepción, alícuotas y exenciones a diciembre de 2025 (Moore Venezuela)](https://www.moore-venezuela.com/wp-content/uploads/sites/15/2025/12/156-IGTF.pdf)
- [Medios digitales para facturas y otros documentos: órdenes de entrega y guías de despacho (PwC, 2025)](https://www.pwc.com/ve/es/assets/documentos/stl/Nota-de-actualidad-Medios-Digitales-para-Facturas-2025.pdf)
- [Tasas de IVA en Venezuela: qué bienes van al 8 %](https://ivacalculator.com/venezuela/tasas-iva-8-16-31/) (fuente secundaria)
