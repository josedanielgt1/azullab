# Farmacia con impresora fiscal y tasa BCV automática

Revisado el 28-10-2026. Esto no sustituye al contador ni al distribuidor de la máquina. Lo marcado *confirmar* depende de ellos.

## 1. Por qué la farmacia usa impresora fiscal

- La **Providencia 0071** (art. 8) obliga a usar máquina fiscal a quien **vende productos farmacéuticos** al consumidor final. Rige hasta el 18-04-2027.
- La **Providencia SNAT/2026/00093** (G.O. 43.484), que rige desde el 19-04-2027, deja elegir el medio, y la **máquina fiscal sigue siendo válida** (art. 4.2).
- Las reglas técnicas de la máquina son las de la **Providencia SNAT/2018/0141** (G.O. 41.518), que reemplazó a la 0592.

Con la impresora fiscal la farmacia cumple la norma de hoy y la de abril de 2027, no paga por cada factura y **factura sin internet**, porque la máquina va por cable a la caja.

*Confirmar con el distribuidor:* que se pueda comprar el equipo. En julio de 2026 se informó que el SENIAT había pausado la venta de máquinas nuevas (ver el documento 02).

## 2. Qué hace el sistema y qué norma cubre

| Exigencia | Qué hace la farmacia en Cuadre |
| --- | --- |
| Máquina de un modelo homologado, con número de registro y logotipo fiscal **MH** (0141) | Configuración → Datos fiscales: marca, modelo, **número de registro** (ej. `Z7C0012345`) y distribuidor o servicio técnico autorizado. El ticket termina con `MH` y el registro. |
| El RIF del usuario queda grabado en la memoria fiscal (0141) | El RIF sale de Datos fiscales. Si el RIF cambia, lo tramita el servicio técnico con el SENIAT; el sistema lo advierte. |
| Factura impresa por la máquina, con número consecutivo, fecha y hora (0071, 0141) | La factura la imprime la impresora. Lleva "SENIAT" arriba, el número, fecha y hora, cliente (RIF o cédula, o "consumidor final"), renglones con (E) o (G), base, IVA, total, formas de pago, la referencia en dólares con la tasa BCV usada, y `MH` con el registro. **No lleva número de control**: ese es de la imprenta. |
| Notas de crédito y de débito por la misma máquina, citando la factura (0071) | Cada nota tiene su propio número y cita el número de la factura, su fecha y el registro de la máquina que la emitió. Resta o suma en el Reporte Z del día y en el Libro de Ventas. La devolución vuelve al inventario. |
| **Reporte Z** por cada día de operación, que cierra la jornada (0141) | Botón "Reporte Z" en Facturas y notas, Módulo fiscal y Mi turno. Se hace **una vez al día**; si se intenta otra vez, el sistema dice a qué hora y quién lo hizo. Lleva facturas desde y hasta, cantidad, notas, exento, base, IVA y total neto. |
| **Reporte X** (lectura sin cierre) | Botón "Reporte X": muestra lo vendido hasta el momento sin cerrar. |
| Libro de Ventas: facturas con RIF una por una y consumidor final por **Reporte Z** con el registro de la máquina (Reglamento de la Ley del IVA, art. 77) | El Libro de Ventas pone un renglón por día "Reporte Z N.° 0086 · consumidor final", del primer al último número, con el registro de la máquina en la columna "N.° de control o registro de máquina". Las facturas con RIF van aparte. Se exporta a Excel con las columnas de `Libro de Ventas IVA.xlsx`. |
| **Libro de Control de Reparación y Mantenimiento** en el local (0141) | El libro físico va junto a la máquina. El sistema lleva una copia: instalación, inspecciones y reparaciones, con fecha y técnico. Es un punto del Checklist del SENIAT. |
| Solo el servicio técnico autorizado repara la máquina y cambia el precinto (0141) | Cuando la impresora falla, el sistema avisa que hay que llamar al servicio técnico y anota la reparación en el libro al volver. |
| Mientras la máquina está dañada, se factura con formatos de **imprenta autorizada** con número de control (0071) | Botón "Simular falla de la impresora". La caja pide el número de control preimpreso del talonario, registra la factura y la marca "talonario · impresora en falla". Esas facturas van **una por una** en el Libro de Ventas y no suman en el Reporte Z. No hay PDF que reportar a ninguna imprenta. |
| Orden de entrega (nota de entrega) con número de control (0071) | La impresora fiscal no la emite: se llena en el talonario de órdenes de entrega de imprenta autorizada y el sistema guarda ese número. Cuando se factura, la factura sale por la impresora fiscal. |
| Comprobante no fiscal | Sale aparte, dice "NO ES FACTURA" y cita la factura y la máquina. |

*Confirmar con el distribuidor y el contador:*

- el plazo máximo de reparación (una fuente cita 15 días hábiles, art. 48 de la 0141);
- si hay inspección anual obligatoria (las fuentes no coinciden);
- el formato del talonario para fallas.

## 3. Cómo se conecta la impresora a Cuadre (producción)

La maqueta simula la impresora. En producción:

1. La impresora (por ejemplo The Factory HKA80, Bixolon o Aclas, de un modelo homologado) va por USB o serial a la PC de la Caja 1.
2. En esa PC corre un **servicio local pequeño** con el SDK o la librería del fabricante (por ejemplo `tfhka` de The Factory). La caja web le manda la factura por `http://localhost`.
3. El servicio manda los comandos a la impresora y devuelve número de factura, número de Reporte Z y estado (sin papel, tapa abierta, error de memoria).
4. Cuadre guarda en la nube lo que devolvió la impresora. **Cuadre nunca numera una factura por su cuenta**: el número sale de la memoria fiscal.
5. Si la impresora responde con error, la caja pasa sola al talonario y avisa al dueño.

Hace falta **UPS** para la caja y la impresora: un apagón a mitad de la impresión puede dejar una factura abierta.

## 4. Tasa BCV automática

**¿Hay una API del BCV?** No. El BCV publica la tasa oficial en `bcv.org.ve` cada día hábil, por la tarde (cerca de las 4:30 p. m.), con **fecha valor del día hábil siguiente**. No tiene API pública.

**Qué hace Cuadre:**

- **En producción:** un proceso del servidor (por ejemplo, una función programada de Supabase) lee la tasa de `bcv.org.ve` a las 5:30 p. m. y a las 8:00 a. m. Si falla, usa un servicio de respaldo. Guarda la tasa con su fecha valor en una tabla, y todas las cajas la toman de ahí.
- **En la maqueta:** el navegador consulta dos servicios públicos que copian la tasa del BCV, uno de respaldo del otro:
  - `bcv.today/api/v1/rate.json`, que trae la fecha valor;
  - `ve.dolarapi.com/v1/dolares/oficial`, que trae la hora de publicación: lo publicado desde las 3:00 p. m. se toma como fecha valor del día hábil siguiente.
- Consulta **al abrir y cada 30 minutos**, y al volver el internet.
- La tasa con fecha valor de mañana **queda en espera y entra sola ese día**, no antes.
- Cada cambio queda en un historial con fecha valor, valor, origen (automática o a mano), hora y usuario. **Cada factura guarda la tasa con la que se cobró.**
- **Sin internet**, o si no responde ninguna fuente, la caja sigue con la última tasa guardada y lo dice.
- **Modo manual:** el dueño escribe la tasa. El sistema solo le avisa cuando el BCV publica una nueva.

**Base legal:** la equivalencia en bolívares se calcula con la tasa del BCV del día de la operación (Ley del IVA, art. 25), y la factura indica la tasa usada. Los libros se llevan en bolívares (COT, art. 102). *Confirmar con el contador.*

**Ojo:** esos servicios no son del BCV. Sus propios autores piden verificar el valor contra la fuente oficial. Por eso, en producción, la fuente principal es `bcv.org.ve`.

## Fuentes

- [Providencia SNAT/2018/0141: normas de imprentas y máquinas fiscales (anexo con el texto)](https://www.consultoreswhb.com/wp-content/uploads/2025/01/Providencia-SENIAT-0141-Normativa-Imprentas-Autorizadas-e-Impresoras-Fiscales.pdf)
- [Gerencia y Tributos: obligaciones del usuario de una máquina fiscal](https://gerenciaytributos.blogspot.com/2019/09/obligaciones-usuario-maquinas-fiscales.html)
- [Gerencia y Tributos: deberes formales del usuario de la máquina fiscal](https://gerenciaytributos.blogspot.com/2021/07/deberes-formales-tributarios-usuario-maquina-fiscal.html)
- [Gerencia y Tributos: inspección anual de la máquina fiscal](https://gerenciaytributos.blogspot.com/2024/10/quien-solicita-y-paga-la-inspeccion-anual-de-la-maquina-fiscal.html)
- [Travieso Evans: memo sobre la normativa de imprentas y máquinas fiscales (G.O. 41.518)](http://www.traviesoevans.com/memos/memo-normativa-imprenta-y-maquinas-fiscales-para-facturas-y-otros-doc.pdf)
- [Adaptapro: Libro de Ventas con Reportes Z](https://adaptaproerp.com/blog_libro_de_ventas_reportes_zeta_maquina_fiscal/)
- [Providencia 0071, art. 8 (venta de productos farmacéuticos)](https://www.mileoconsultores.com/wp-content/uploads/2015/02/PA00071_2011.pdf)
- [Finanzas Digital: el SENIAT levanta el uso obligatorio de máquinas fiscales (G.O. 43.484)](https://finanzasdigital.com/seniat-levanta-uso-obligatorio-maquinas-fiscales-gaceta-oficial/)
- [bcv-api (bcv.today): API JSON no oficial de la tasa del BCV, con fecha valor](https://github.com/grupoclip/bcv-api)
