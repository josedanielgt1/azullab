# Retenciones SENIAT: qué le toca a Azullab y qué hace Cuadre

**Actualizado el 27-10-2026.** Hay dos retenciones distintas y se confunden mucho:

| | Retención de **IVA** | Retención de **ISLR** |
| --- | --- | --- |
| Quién retiene | Solo los **agentes designados**: contribuyentes especiales (SPE) y unos pocos casos más | **Cualquier empresa** que pague ciertos conceptos: alquiler, honorarios, servicios, fletes, publicidad… |
| ¿Azullab retiene? | **No**, mientras sea contribuyente ordinario | **Sí**, si es una compañía (C.A.) |
| ¿A Azullab le retienen? | A veces: un cliente especial que le compre productos **gravados** | Casi nunca: vender mercancía no lleva retención de ISLR |
| En Cuadre | Base: registrar el comprobante recibido. Módulo especial: retener | **Base**: calcular, emitir el comprobante y la relación del mes |

> **Corrección a los documentos anteriores:** la guía `00` y el documento `02` ponían las retenciones de ISLR dentro del módulo de contribuyente especial. Eso estaba mal. Toda empresa que paga alquiler u honorarios retiene ISLR, sea especial u ordinaria. **Va en la base de Cuadre.** Ya quedó corregido en los dos documentos y en la maqueta.

---

## 1. Retención de IVA

### La norma vigente

- **Providencia SNAT/2025/000054** (G.O. 43.171 del 16-07-2025, vigente desde el 01-08-2025). Deroga la SNAT/2015/0049 y **mantiene sus reglas**: exclusiones, porcentajes, momento de retener, comprobantes y sanciones. Lo nuevo es que también son agentes los **contribuyentes especiales que son personas naturales con firma personal**.
- **Quién retiene:** los contribuyentes especiales designados. Hay casos aparte, como los compradores de metales preciosos, que no le tocan a una farmacia.
- **Cuánto:** el **75 % del IVA** de la factura. Se retiene el **100 %** si la factura no discrimina el IVA, no cumple los requisitos formales, no trae número de control o el proveedor no está inscrito en el RIF.
- **Cuándo:** al **pagar o abonar en cuenta**, lo que ocurra primero, no en la fecha de la factura.
- **No se retiene:** en compras **exentas, exoneradas o no sujetas**, como los medicamentos. Hay otras exclusiones (caja chica, servicios domiciliados en cuenta…), pero esa es la que importa aquí.

### Lo que significa para Azullab

1. **Azullab no retiene IVA a las droguerías.** No es agente, así que paga sus facturas completas.
2. **Un cliente especial puede retenerle IVA a Azullab**, pero solo en lo **gravado al 16 %** (pañales, champú, protector solar). En medicamentos no hay IVA que retener.
   - Ejemplo: una empresa especial compra pañales por Bs 10.000 + IVA Bs 1.600. Paga Bs 10.400 y entrega un **comprobante de retención por Bs 1.200** (el 75 % de 1.600).
   - Azullab **anota el comprobante en el Libro de Ventas**: la columna ya existe en la plantilla. En su declaración de IVA **descuenta esos Bs 1.200** del impuesto a pagar.
3. **Depuración del padrón (Providencia SNAT/2026/00099, desde el 01-11-2026):** el SENIAT reduciría los especiales de unos 132.000 a 44.000. Algunos clientes que hoy retienen **dejarán de hacerlo**. Por eso, en Cuadre, "es agente de retención" es una **marca en la ficha del cliente** que se puede cambiar, no una regla fija.

### Si Azullab llega a ser contribuyente especial (módulo)

Con el módulo activo, Cuadre también:

- **retiene el 75 % o el 100 %** al registrar el pago a cada proveedor de bienes o servicios gravados;
- emite el **comprobante** con número de 14 dígitos: año y mes más 8 dígitos correlativos (por ejemplo, `20261100000001`). Se entrega a más tardar en los **dos primeros días hábiles del período siguiente**, y se puede emitir uno solo por quincena por proveedor;
- llena las columnas de retención del **Libro de Compras** (ya están en la plantilla);
- prepara la declaración **quincenal** según el **calendario de contribuyentes especiales**, que se presenta en el portal del SENIAT.

*Los plazos exactos y el formulario cambian con cada calendario anual: confirmarlos con el contador.*

---

## 2. Retención de ISLR (Decreto 1.808)

### Quién retiene

El Decreto 1.808 obliga a los **"deudores o pagadores"** de ciertos conceptos a retener al **pagar o abonar en cuenta**. Una **C.A.** como Azullab **es agente de retención de ISLR** aunque sea contribuyente ordinario.

### Lo que paga una farmacia y su retención

| Concepto (Decreto 1.808) | A persona natural residente | A empresa domiciliada | Ejemplo en Azullab |
| --- | --- | --- | --- |
| Honorarios profesionales | 3 % menos sustraendo | 5 % | Contador, abogado |
| Alquiler de inmuebles | 3 % menos sustraendo | 5 % | Local comercial |
| Servicios (contratistas) | 1 % menos sustraendo | 2 % | Técnico del aire, mantenimiento, fumigación |
| Fletes | 1 % menos sustraendo | 3 % | Transporte de mercancía, cuando no lo paga la droguería |
| Publicidad y propaganda | 3 % menos sustraendo | 5 % | Agencia, emisora local |

**Compra de mercancía a droguerías:** **no** lleva retención de ISLR. Es compra de bienes.

### El sustraendo y el mínimo (solo personas naturales)

- **Unidad tributaria (UT): Bs 43**, vigente desde junio de 2025. No encontré un reajuste posterior; **hay que verificarlo**, porque si la UT cambia, cambian el sustraendo y el mínimo.
- **Sustraendo** = UT × porcentaje × 83,3334:
  - al 3 %: **Bs 107,50**;
  - al 1 %: **Bs 35,83**.
- **Mínimo:** a una persona natural solo se le retiene si el pago pasa de **Bs 3.583,33** (UT × 83,3334). A las empresas se les retiene en todos los pagos.
- Si el pago se hace en dólares, la retención **se calcula en bolívares** a la tasa BCV del día del pago.

### Ejemplos con los gastos de octubre de la maqueta

| Pago | Monto | Tasa | Base Bs | % | Sustraendo | **Retenido Bs** | Se le paga Bs |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Alquiler del local (persona natural) | $650 | 862,15 | 560.397,50 | 3 % | 107,50 | **16.704,42** | 543.693,08 |
| Honorarios del contador (persona natural) | $120 | 881,10 | 105.732,00 | 3 % | 107,50 | **3.064,46** | 102.667,54 |
| Técnico del aire (persona natural) | $60 | 868,40 | 52.104,00 | 1 % | 35,83 | **485,21** | 51.618,79 |

En la práctica, al arrendador se le pagan unos **$19,38 menos** y Azullab entrega ese dinero al SENIAT a nombre de él. Él lo descuenta de su propia declaración de ISLR con el comprobante.

### Lo que hay que entregar

1. **Comprobante de retención** al proveedor por cada retención (según lo investigado, dentro de los 3 días hábiles siguientes al pago; *confirmar el plazo con el contador*).
2. **Enterar** (pagar) lo retenido al SENIAT. *El plazo exacto para un contribuyente ordinario lo confirma el contador*: no lo encontré en una fuente confiable y no lo voy a inventar.
3. **Relación mensual de retenciones** en el portal del SENIAT (se carga como archivo XML). *Confirmar el formato vigente.*
4. **ARCV** (comprobante anual) a cada proveedor y empleado al cerrar el año.

### Sueldos de los empleados

La retención de ISLR sobre sueldos (AR-I), la contribución para pensiones y las demás cargas de la nómina están en **`nomina/05 - Módulo de nómina.md`**. La nómina es un **módulo aparte** que se cobra aparte.

---

## 3. Qué hace Cuadre

### En la base (contribuyente ordinario)

- **Gastos con retención de ISLR:** al registrar un gasto, se elige el concepto y si el proveedor es persona natural o empresa. Cuadre calcula la retención con el sustraendo y el mínimo, dice **cuánto se le paga** y genera el **comprobante numerado en PDF** para enviarlo por WhatsApp o correo.
- **Retenciones del mes:** una lista con lo retenido, lo que falta por enterar y los comprobantes entregados.
- **Relación mensual** para el portal del SENIAT y **ARCV** en enero.
- **Tabla de conceptos editable** (porcentajes, UT y sustraendo), para no depender de una actualización del sistema cuando cambie la UT.
- **Comprobantes de IVA recibidos:** se anotan en la venta o en el cobro, pasan solos al Libro de Ventas y se restan en el resumen para declarar.

### En el módulo de contribuyente especial

- Retención de IVA al 75 % o al 100 %, con comprobante de 14 dígitos, Libro de Compras y declaración quincenal.
- IGTF de 3 % (ya estaba en el módulo).

### En la maqueta

**Ganancias y gastos** ahora tiene:

- el panel **"Retenciones de ISLR · octubre"**, con el alquiler, el contador y el técnico del ejemplo;
- en **"Registrar gasto"**, el campo **"Retención de ISLR"**, que calcula la retención y lo que se le paga mientras se escribe el monto.

---

## 4. Preguntas para el contador de Azullab

1. ¿Azullab está constituida como **C.A.** o como **firma personal**? Si es firma personal, ¿lleva contabilidad y retiene ISLR?
2. ¿Está o puede estar en el **padrón de contribuyentes especiales**? Revisarlo en el portal después del 01-11-2026.
3. ¿El arrendador del local es **persona natural o empresa**? Cambia el porcentaje (3 % o 5 %).
4. **Plazo para enterar** las retenciones de ISLR y formato del archivo de la relación mensual.
5. ¿Algún cliente actual (empresa, colegio, alcaldía) **le retiene IVA** a la farmacia?

---

## Fuentes

- [Forvis Mazars: Providencia SNAT/2025/000054, agentes de retención del IVA](https://www.forvismazars.com/ve/es/insights/forvis-mazars-insights/fmi-0825-providencia-agentes-de-retencion-del-iva)
- [Baker McKenzie: nueva designación de agentes de retención de IVA (2025)](https://www.bakermckenzie.com/en/insight/publications/alerts/2025/08/venezuela-new-vat-withholding-designation)
- [KPMG: Noticias tributarias, julio 2025](https://assets.kpmg.com/content/dam/kpmg/ve/pdf/2025/8/Noticias%20tributarias%20julio%202025.pdf)
- [Acceso a la Justicia: agentes de retención IVA, firmas personales especiales](https://accesoalajusticia.org/agentes-retencion-iva-a-las-personas-calificadas-como-sujetos-pasivos-especiales-constituidas-como-firma-personal/)
- [Retenciones de IVA en Venezuela: 75 %, 100 % y momento del pago](https://ivacalculator.com/venezuela/retenciones-iva/) (fuente secundaria; sus fechas tienen errores)
- [Acceso a la Justicia: reajuste de la unidad tributaria a Bs 43](https://accesoalajusticia.org/reajustado-el-valor-de-la-unidad-tributaria-u-t-a-bs-4300/)
- [Finanzas Digital: unidad tributaria en Bs 43](https://finanzasdigital.com/reajuste-unidad-tributaria-venezuela-43-bolivares/)
- [Forvis Mazars: tabla de retenciones de ISLR (Decreto 1.808, estructura y porcentajes)](https://www.forvismazars.com/ve/es/insights/forvis-mazars-insights/tabla-de-retenciones-islr-ut-9-00-bs-may-2023)
