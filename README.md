# Grupo Azullab · sistemas Cuadre

Maquetas navegables (HTML, solo visual, con datos de muestra) de los sistemas para el Grupo Empresarial Azullab, en La Azulita, Mérida. Están hechas con el diseño **Papel Fiscal** de Cuadre.

Abre `index.html` en el navegador para escoger entre los tres sistemas.

**Un RIF por negocio.** La farmacia, el laboratorio y el CrossFit son tres contribuyentes distintos. Cada sistema tiene, con su propio RIF: datos fiscales en Configuración, factura con equivalencia en divisas, notas de crédito y de débito, talonario de contingencia, Libro de Ventas, Libro de Compras, retenciones de ISLR, borrador de la forma 30, calendario fiscal, checklist del SENIAT y exportación a Excel. El tablero del dueño muestra el Grupo Azullab junto, solo para gerencia. El código fiscal es el mismo en los tres archivos (bloque `FX:INICIO`); lo propio de cada negocio va en `FX_SYS`, incluido el medio de facturación (`medio`): **los tres facturan con impresora fiscal**, una por RIF (Reporte X, Reporte Z diario, registro de la máquina y talonario solo si la impresora falla). Detalle en `seniat/06 - Un RIF por negocio (Grupo Azullab).md` y `seniat/07 - Impresora fiscal y tasa BCV.md`.

| Archivo | Qué es |
| --- | --- |
| `farmacia.html` | Azullab Farmacia: caja con factura por impresora fiscal (Reportes X y Z) y lista de productos con su propia barra de desplazamiento, tasa BCV que se actualiza sola con su fecha valor, cotizaciones y comprobante no fiscal, productos con precio por % de ganancia y varios códigos de barras, inventario por lote y vencimiento con salidas por motivo, compras con opciones cuando cambia el costo, clientes, fiscal, ganancias y gastos, bancos, sin conexión, usuarios y permisos editables, configuración, fase 2, el módulo de nómina aparte y versión de teléfono |
| `laboratorio.html` | Azullab Laboratorio Clínico: factura por impresora fiscal, atención sin cita, ficha completa del paciente, datos de la visita, toma de muestras con etiquetas, carga y validación de resultados, informe firmado con QR, reactivos, caja y fase 2 |
| `crossfit.html` | Azullab CrossFit (regalo para el grupo): pizarra del día que escribe el coach con ejemplo visual de cada movimiento, app del socio en el teléfono (ve la rutina, reserva clase, anota su resultado), registro de socios, membresías con aviso de vencimiento, cobros con factura de impresora fiscal e IVA de 16 %, notas de crédito, libros y checklist del SENIAT con su propio RIF, y entrada con cédula. Abre `crossfit.html#socio` para entrar directo a la vista del socio |
| `papel-fiscal/` | Sistema de diseño de Cuadre: tokens (colores, letras) y componentes CSS |
| `seniat/` | Guías fiscales (SENIAT, retenciones, trabajo sin internet, un RIF por negocio, impresora fiscal y tasa BCV; la de imprenta digital queda como estudio previo) y libros de compras, ventas e inventario en Excel |
| `recipes/` | Base de datos de récipes (documento y SQL para Supabase) |
| `nomina/` | Módulo de nómina: horas extra, bono nocturno, liquidaciones, aumentos, archivo TXT para el banco y parámetros de ley |
| `capturas/movil/` | Capturas de la farmacia en el teléfono (390 px), antes y después de la versión móvil |
| `propuesta/` | Propuesta económica de la farmacia: precios, mensualidad, forma de pago y condiciones del servicio |

Cada HTML es un solo archivo: estilos, datos de muestra y lógica van adentro. No necesita servidor; solo hace falta internet para cargar las letras.

Ningún dato de pacientes, clientes o ventas es real.
