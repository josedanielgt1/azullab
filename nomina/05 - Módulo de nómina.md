# Módulo de nómina y empleados (se cobra aparte)

**Qué es:** la nómina completa de la farmacia dentro de Cuadre. Incluye la ficha de cada empleado, la quincena calculada sola, los recibos por WhatsApp, los aportes, las prestaciones y un calendario de pagos con avisos. **No va en la propuesta base**: se ofrece como módulo aparte, se cobra aparte y se puede contratar desde el inicio o después.

**A quién se le vende:** a la farmacia que no quiere depender del contador para cada quincena, o que quiere saber **cuánto le cuesta de verdad cada empleado**. Si la nómina la lleva el contador, Cuadre solo registra el pago como un gasto más.

---

## 1. Lo que trae

| Pantalla | Qué hace |
| --- | --- |
| **Empleados** | Ficha de cada trabajador con cédula, cargo, fecha de ingreso, antigüedad, salario, bonos, cestaticket, cargas familiares, forma de pago y AR-I. Muestra el **costo real al mes** de cada uno: lo que cobra más pensiones, aportes y provisiones. También tiene asistencia con PIN, constancia de trabajo en PDF y avisos de documentos. |
| **Nómina · Quincena** | La quincena calculada sola en cuatro pasos: calcular, revisar, pagar y enviar recibos. Al aprobarla, el pago queda registrado como gasto en Ganancias y gastos. Cada empleado recibe su **recibo por WhatsApp**. |
| **Nómina · Aportes y retenciones** | Seguro social, paro forzoso, FAOV, INCES, contribución para pensiones y retención de ISLR del mes, con la parte del trabajador, la del patrono y a quién se le paga. |
| **Nómina · Prestaciones y vacaciones** | Garantía de prestaciones acumulada, vacaciones, bono vacacional y utilidades del año de cada empleado. |
| **Nómina · Calendario** | Qué se paga, cuándo y cuánto: quincenas, cestaticket, IVSS, FAOV, pensiones, ISLR y utilidades. El dueño recibe un aviso antes de cada fecha. |

Solo el **dueño** ve este módulo. El regente, los cajeros y el almacén no ven sueldos.

---

## 2. Las reglas que calcula

*Todos los porcentajes se configuran en el sistema y se confirman con el contador de cada cliente.*

### Lo que se le descuenta al trabajador

| Concepto | Porcentaje | Base |
| --- | --- | --- |
| Seguro social (IVSS) | 4 % | Salario, con tope de 5 salarios mínimos |
| Paro forzoso (Régimen Prestacional de Empleo) | 0,5 % | Salario, con tope de 10 salarios mínimos |
| FAOV (vivienda, BANAVIH) | 1 % | Salario |
| INCES | 0,5 % | Utilidades, cuando se pagan |
| ISLR | Según su AR-I | Salario normal, si pasa de 1.000 UT al año |

### Lo que paga la farmacia

| Concepto | Porcentaje | Base |
| --- | --- | --- |
| Seguro social (IVSS) | 9 % (riesgo mínimo; 10 % o 11 % en riesgo medio o máximo) | Salario, con tope de 5 salarios mínimos |
| Paro forzoso | 2 % | Salario, con tope de 10 salarios mínimos |
| FAOV | 2 % | Salario |
| INCES | 2 % | Nómina; solo si tiene **5 o más trabajadores** (Azullab tiene 4) |
| **Contribución para pensiones** | **9 %** | **Salario y bonos**, con un mínimo del ingreso mínimo integral ($240) por trabajador |

**Lo que hay que explicarle al dueño:** como el salario mínimo sigue en **Bs 130**, los topes del seguro social dan montos pequeños. La carga grande es la **contribución para pensiones**, porque incluye los bonos. En la maqueta, con 4 empleados y $1.800 al mes, la contribución es de **$162 al mes** y todo lo demás no llega a $2.

### Retención de ISLR sobre sueldos (AR-I)

- La farmacia, como patrono, retiene a quien gane **más de 1.000 UT al año**. Con la UT en Bs 43, eso es **Bs 43.000 al año** (≈ Bs 3.583 al mes, unos $4).
- Cada trabajador llena el **AR-I**: estima su ingreso del año y elige el desgravamen único (774 UT) o el detallado. Se le resta la rebaja personal (10 UT) y 10 UT por cada carga familiar. De ahí sale **un porcentaje fijo** que se le descuenta en cada pago (Decreto 1.808).
- Si no lo llena, el patrono hace el cálculo por su cuenta. En enero se le da el **ARC**.
- **Base:** el TSJ ha dicho varias veces que es el **salario normal**, o sea, lo que se paga de forma regular y permanente. El SENIAT intenta sumar las utilidades y el bono vacacional.
- Desde mayo de 2026, el ingreso mínimo de $240 se paga como bonos: $200 del bono contra la guerra económica y $40 de cestaticket. Esos bonos no son salario.
- Si se paga un sueldo en dólares **como salario**, el impuesto sube rápido porque la UT no se actualiza. Con desgravamen único, sin cargas familiares y a tasa 881,88:

| Salario normal al mes | Impuesto en el año | Porcentaje que se retiene |
| --- | --- | --- |
| $10 | ≈ $6 | ≈ 5 % |
| $25 | ≈ $48 | ≈ 16 % |
| $50 | ≈ $148 | ≈ 25 % |
| $100 | ≈ $352 | ≈ 29 % |
| $200 | ≈ $760 | ≈ 32 % |

**Cuánto del pago es salario y cuánto bono lo decide el contador o un abogado laboral**, no el sistema. Cuadre calcula con lo que ellos definan.

### Prestaciones, vacaciones y utilidades (LOTTT)

- **Garantía de prestaciones:** 15 días de salario por cada trimestre (art. 142).
- **Vacaciones:** 15 días hábiles más 1 por cada año, hasta 15 días adicionales (art. 190).
- **Bono vacacional:** 15 días de salario más 1 por cada año, hasta 30 (art. 192).
- **Utilidades:** 30 días de salario como mínimo al año (art. 131); el INCES le descuenta 0,5 % al trabajador.

---

## 3. Cómo se ve en la maqueta

En el menú del dueño aparece el grupo **Nómina** con la marca **Aparte**, y cada pantalla dice **Módulo aparte** arriba:

- **Empleados:** 4 empleados con su ficha. Toca uno para ver lo que cuesta al mes. Kevin cobra $390 y le cuesta a la farmacia $427.
- **Nómina:** la segunda quincena de octubre. Pulsa **Aprobar y pagar** y luego **Enviar recibos por WhatsApp**. Cada fila tiene su **Recibo**. Revisa también las pestañas de aportes, prestaciones y calendario.
- **Alcance de la propuesta:** un panel aparte, "Módulo de nómina y empleados · Se cobra aparte", con la lista de lo que incluye.

Ganancias y gastos quedó limpia: la nómina aparece ahí solo como un gasto.

---

## 4. Cómo venderlo

- **Argumento principal:** "Sepa cuánto le cuesta de verdad cada empleado y pague la quincena en un minuto, con el recibo en el WhatsApp de cada uno".
- **Forma de cobro sugerida:** una instalación y luego una mensualidad por empleado. Así crece con la farmacia y sirve igual para el laboratorio y los demás negocios del grupo.
- **Para combinar:** asistencia con PIN, que es el mismo concepto del sistema de asistencia de la alcaldía.

---

## 5. Preguntas para el contador del cliente

1. ¿Cuánto del pago es **salario** y cuánto **bono**?
2. ¿Qué porcentaje de la **contribución para pensiones** rige en 2026? ¿Incluye el cestaticket en la base?
3. ¿En qué nivel de **riesgo del IVSS** está inscrita la farmacia (9 %, 10 % u 11 %)?
4. ¿Ya tienen el **AR-I** de cada trabajador?
5. ¿Quiere seguir llevando la nómina él, o prefiere revisar lo que calcula Cuadre?

---

## Fuentes

- [Deducciones del salario en Venezuela: IVSS, paro forzoso, FAOV e INCES (TopTrabajos, marzo 2026)](https://www.toptrabajos.com/ve/blog/deducciones-salario-venezuela/)
- [FAOV y BANAVIH 2026: aportes en la nómina (G-Talent)](https://www.g-talent.net/blogs/finanzas-administracion/faov-banavih-venezuela-2026-aportes-nomina)
- [Vacaciones y bono vacacional según la LOTTT (TopTrabajos)](https://www.toptrabajos.com/ve/blog/pago-vacaciones-venezuela/)
- [Nayma Consultores: AR-I y retención de ISLR sobre sueldos (actualizado en enero de 2026)](https://naymaconsultores.com/planilla-ari-islr-sueldos-salarios-venezuela/)
- [PwC: cápsula tributaria de ISLR, marzo 2026 (salario normal, TSJ y SENIAT)](https://www.pwc.com/ve/es/assets/documentos/stl/PwC-Venezuela-Capsula%20Tributaria-ISLR-MAR2026.pdf)
- [Acceso a la Justicia: el TSJ ratifica que el ISLR se calcula sobre el salario normal](https://accesoalajusticia.org/tsj-ratifica-que-el-calculo-del-islr-es-sobre-el-salario-normal/)
- [Bloomberg Línea: el ingreso mínimo de 2026 se paga con bonos](https://www.bloomberglinea.com/latinoamerica/venezuela/como-se-pagara-el-salario-minimo-2026-en-venezuela-aumento-funcionara-con-bonos/)
- [Acceso a la Justicia: Ley de Protección de las Pensiones de Seguridad Social](https://accesoalajusticia.org/ley-de-proteccion-de-las-pensiones-de-seguridad-social/)
- [Acceso a la Justicia: contribución especial fijada en 9 %](https://accesoalajusticia.org/fijado-en-9-el-monto-de-la-contribucion-especial-prevista-en-la-ley-de-proteccion-de-las-pensiones-de-seguridad-social/)
- [Acceso a la Justicia: unidad tributaria en Bs 43](https://accesoalajusticia.org/reajustado-el-valor-de-la-unidad-tributaria-u-t-a-bs-4300/)
