# Módulo de nómina y empleados (se cobra aparte)

**Qué es:** la nómina completa de la farmacia dentro de Cuadre. Incluye la ficha editable de cada empleado, los aumentos, las horas extra y novedades, la quincena calculada sola, el pago con archivo para el banco, los recibos por WhatsApp, los aportes, las prestaciones, las liquidaciones y un calendario de pagos con avisos. **No va en la propuesta base**: se ofrece como módulo aparte, se cobra aparte y se puede contratar desde el inicio o después.

**A quién se le vende:** a la farmacia que no quiere depender del contador para cada quincena, o que quiere saber **cuánto le cuesta de verdad cada empleado**. Si la nómina la lleva el contador, Cuadre solo registra el pago como un gasto más.

---

## 1. Lo que trae

| Pantalla | Qué hace |
| --- | --- |
| **Empleados** | Ficha de cada trabajador con cédula, cargo, acceso al sistema, jornada, estado, fecha de ingreso, antigüedad, salario, bonos, cestaticket, cargas familiares, AR-I, banco, cuenta y teléfono del pago móvil. **Todo se edita** con el botón *Editar ficha*, y cada cambio queda en el **historial** con la fecha, el motivo y quién lo hizo. Muestra el **costo real al mes** de cada uno. También tiene asistencia con PIN, constancia de trabajo en PDF y avisos de documentos. |
| **Empleados · Aumento de sueldo** | Sube el salario, el bono o el cestaticket por porcentaje, por una suma fija o a un monto nuevo, para todos o para algunos. Antes de aplicarlo muestra cuánto más le cuesta a la farmacia al mes. Si la fecha es futura, queda **programado** y entra solo ese día. |
| **Nómina · Quincena** | La quincena calculada sola en cuatro pasos: novedades, revisar, pagar y enviar recibos. Al pagar, cada empleado cobra por donde dice su ficha: **archivo TXT para el banco**, pago móvil o efectivo. El pago queda registrado como gasto en Ganancias y gastos y cada empleado recibe su **recibo por WhatsApp**, con cada asignación y cada descuento. |
| **Nómina · Horas extra y novedades** | Horas extra de día y de noche, horas nocturnas (bono nocturno), feriados y descansos trabajados, faltas y adelantos. El monto se calcula solo y avisa si pasa de los límites de la ley. |
| **Nómina · Aportes y retenciones** | Seguro social, paro forzoso, FAOV, INCES, contribución para pensiones y retención de ISLR del mes, con la parte del trabajador, la del patrono y a quién se le paga. |
| **Nómina · Prestaciones y vacaciones** | Garantía de prestaciones acumulada, vacaciones, bono vacacional y utilidades del año de cada empleado. |
| **Nómina · Liquidación** | Al egresar un empleado: prestaciones (garantía o cálculo final, el mayor), intereses, vacaciones y bono vacacional fraccionados, utilidades fraccionadas e indemnización si el despido es injustificado. Con *Registrar egreso*, sale de la nómina y su usuario se bloquea solo. |
| **Nómina · Calendario** | Qué se paga, cuándo y cuánto: quincenas, cestaticket, IVSS, FAOV, pensiones, ISLR y utilidades. El dueño recibe un aviso antes de cada fecha. |
| **Nómina · Parámetros de ley** | Salario mínimo, ingreso mínimo integral, cestaticket, unidad tributaria, riesgo del IVSS, contribución para pensiones, recargos de horas extra, bono nocturno y feriados, días de utilidades e interés de prestaciones. Cuando sale un decreto se cambia aquí y **todo se recalcula**, sin llamar al programador. No deja poner menos de lo que pide la ley. |

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

### Horas extra, bono nocturno, feriados y faltas (LOTTT)

| Concepto | Cómo se paga | Base legal |
| --- | --- | --- |
| Hora extra de día | Hora normal + 50 % como mínimo | Art. 118 |
| Hora extra de noche | Hora normal + 30 % (nocturna) + 50 % (extra) | Arts. 117 y 118 |
| Hora nocturna (de 7 pm a 5 am) | Recargo de 30 % como mínimo | Art. 117 |
| Feriado o día de descanso trabajado | El día + 50 % de recargo, y otro día libre | Art. 120 |
| Falta sin justificar | Se descuenta el día | — |
| Adelanto o préstamo | Se descuenta en dólares de los bonos | — |

- **Hora normal:** salario diario entre 8 (jornada diurna).
- **Límites (art. 178):** máximo 10 horas extra por semana, 100 al año y 10 horas de trabajo por día. Cuadre avisa en rojo si se pasa.
- **Jornadas (art. 173):** diurna de 8 h (40 por semana), nocturna de 7 h (35) y mixta de 7,5 h (37,5).
- **Lo práctico en una farmacia:** cuando le toca **turno**, el que trabaja de noche, el fin de semana o un feriado cobra con estos recargos. Con la asistencia por PIN, las horas salen solas de la hora de entrada y salida.
- Las horas extra, el bono nocturno y los feriados suman al salario, así que también pagan seguro social, FAOV e ISLR.

### Liquidación al egresar (LOTTT)

- **Prestaciones (art. 142):** se compara la garantía (15 días por trimestre, más 2 días por año desde el segundo año) con el cálculo final (30 días por año o fracción de más de 6 meses, con el último salario integral). Se paga **el mayor**.
- **Intereses (art. 143):** sobre la garantía, con la tasa que publica el BCV.
- **Vacaciones y bono vacacional fraccionados (art. 196).**
- **Utilidades fraccionadas (art. 131).**
- **Indemnización por despido injustificado (art. 92):** igual al monto de las prestaciones.
- **Salario integral:** salario más la parte diaria de utilidades y de bono vacacional.
- **Ojo:** como el salario en bolívares es bajo y los bonos no cuentan, la liquidación en dólares sale pequeña. Si el contador define que parte del bono es salario, sube.

### Prestaciones, vacaciones y utilidades (LOTTT)

- **Garantía de prestaciones:** 15 días de salario por cada trimestre (art. 142).
- **Vacaciones:** 15 días hábiles más 1 por cada año, hasta 15 días adicionales (art. 190).
- **Bono vacacional:** 15 días de salario más 1 por cada año, hasta 30 (art. 192).
- **Utilidades:** 30 días de salario como mínimo al año (art. 131); el INCES le descuenta 0,5 % al trabajador.

---

## 3. Pagar por el banco: archivo TXT o API

**Lo que sí funciona hoy: el archivo TXT.** Los bancos venezolanos tienen pago de nómina para empresas en su banca en línea:

- **Banesco** (BanescOnline Empresa): se sube un archivo plano .txt con el formato de sus manuales, o un .zip con varios. Los pagos se pueden programar para el día que se indique, el resultado llega por correo y el servicio cobra una comisión. Para pagar a cuentas de otros bancos, la empresa debe estar afiliada al pago a proveedores.
- **Banco de Venezuela** (BDVenlínea Empresas): servicio de abono de nómina, también programable. Se tramita con el ejecutivo de la agencia.
- Los sistemas de nómina venezolanos ya generan el archivo para Banesco, Banco de Venezuela, Mercantil, Provincial, BNC, Bancaribe, Sofitasa y otros. Cuadre hace lo mismo.

**Cómo queda en Cuadre:** al pagar la quincena, Cuadre arma el archivo con todos los que cobran por transferencia. El dueño lo descarga, lo sube en la banca en línea de su banco y lo aprueba con su token. El banco paga a todos de una vez. A los que cobran por pago móvil, Cuadre les muestra los datos listos para copiar, y a los que cobran en efectivo, el recibo para firmar.

**Lo que hay que pedirle a la farmacia:** el **manual de formato de archivo** que le entrega su banco al afiliarse al pago de nómina. En la maqueta el archivo es de muestra; el definitivo se arma con ese manual.

**¿Y la API del banco para pagar directo?** Hoy los bancos venezolanos abren sus API sobre todo para **cobrar** (pago móvil C2P, botón de pago) y para **verificar** pagos móviles: Mercantil, Banco de Venezuela, BNC, Bancaribe, Tesoro, R4 y Activo tienen algo de eso. No encontramos un banco que ofrezca de forma abierta una API para **enviar** pagos de nómina. Eso pide un convenio especial con el banco. Si la farmacia lo consigue, Cuadre se conecta y el archivo ya no hace falta. **No hay que prometerlo en la propuesta.**

---

## 4. Cómo se ve en la maqueta

En el menú del dueño aparece el grupo **Nómina** con la marca **Aparte**, y cada pantalla dice **Módulo aparte** arriba:

- **Empleados:** 4 empleados con su ficha. Toca uno para ver lo que cuesta al mes: Kevin cobra $390 y le cuesta a la farmacia $427. Pulsa **Editar ficha** y cámbiale el cargo, el acceso al sistema o el salario: el cambio aparece en su historial y en Usuarios. Prueba **Aumento de sueldo** con 20 % desde el 01/11 y mira cuánto más cuesta.
- **Nómina · Horas extra:** Kevin tiene 6 horas extra y un adelanto de $20, Mariela 7 horas de noche y un descanso trabajado (turno de la farmacia), Wilmer una falta. Escribe 25 horas a alguien y sale el aviso de que pasa el límite semanal.
- **Nómina · Quincena:** pulsa **Aprobar y pagar**: salen los grupos de transferencia, pago móvil y efectivo. Con **Generar archivo TXT** se ve el archivo para Banesco. Luego **Marcar como pagada** y **Enviar recibos por WhatsApp**. Cada fila tiene su **Recibo** con las horas extra y los descuentos.
- **Nómina · Liquidación:** elige un empleado, el motivo y la fecha. Con *Despido injustificado* aparece la indemnización.
- **Nómina · Parámetros de ley:** cambia el salario mínimo y todo se recalcula. Si pones 40 % en horas extra, no lo deja.
- **Alcance de la propuesta:** un panel aparte, "Módulo de nómina y empleados · Se cobra aparte", con la lista de lo que incluye.

Ganancias y gastos quedó limpia: la nómina aparece ahí solo como un gasto.

---

## 5. Cómo venderlo

- **Argumento principal:** "Sepa cuánto le cuesta de verdad cada empleado y pague la quincena en un minuto, con el archivo para el banco listo y el recibo en el WhatsApp de cada uno".
- **Para el dueño que teme a los decretos:** cuando cambie el salario mínimo o un porcentaje, lo cambia él mismo en *Parámetros de ley* y todo se recalcula.
- **Forma de cobro sugerida:** una instalación y luego una mensualidad por empleado. Así crece con la farmacia y sirve igual para el laboratorio y los demás negocios del grupo.
- **Para combinar:** asistencia con PIN, que es el mismo concepto del sistema de asistencia de la alcaldía.

---

## 6. Preguntas para el contador del cliente

1. ¿Cuánto del pago es **salario** y cuánto **bono**?
2. ¿Qué porcentaje de la **contribución para pensiones** rige en 2026? ¿Incluye el cestaticket en la base?
3. ¿En qué nivel de **riesgo del IVSS** está inscrita la farmacia (9 %, 10 % u 11 %)?
4. ¿Ya tienen el **AR-I** de cada trabajador?
5. ¿Quiere seguir llevando la nómina él, o prefiere revisar lo que calcula Cuadre?
6. ¿Con qué banco paga la nómina y ya tiene el manual del archivo?
7. ¿Las horas extra se pagan con el 50 % de la ley o con más, por contrato?
8. ¿Qué tasa de interés de prestaciones del BCV está usando este mes?

---

## Fuentes

- [Banesco: Pago de Nómina en BanescOnline Empresa](https://www.banesco.com/empresas/soluciones-digitales/pago-de-nomina/)
- [Banco de Venezuela: pago de nómina por BDVenlínea Empresas](https://www.bancodevenezuela.com/index.html@p=3491.html)
- [eFactory: archivos bancarios de nómina para bancos venezolanos](http://factorysoftve.com/software-de-nomina-y-rrhh-en-la-nube/como-emitir-archivos-bancarios-de-nomina-con-efactory-software-de-nomina-en-la-nube.html)
- [Cujiware: pasarelas y botones de pago en Venezuela](https://cujiware.com/pasarelas-pago-venezuela)
- [Bancaribe: Open Banking](https://www.bancaribe.com.ve/open-banking)
- [Acceso a la Justicia: horas extras y art. 178 de la LOTTT](https://accesoalajusticia.org/glossary/horas-extras/)
- [Finiquito Justo: guía de horas extra en Venezuela 2026](https://finiquitojusto.com/?p=1746)
- [Clyde & Co: régimen de jornada en Venezuela (marzo 2026)](https://www.clydeco.com/es/insights/2026/03/working-hours-regime-in-venezuela-legal-analysis-o)

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
