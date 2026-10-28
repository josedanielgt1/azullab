# Grupo Azullab · sistemas Cuadre

Maquetas navegables (HTML, solo visual, con datos de muestra) de los sistemas para el Grupo Empresarial Azullab, en La Azulita, Mérida. Están hechas con el diseño **Papel Fiscal** de Cuadre.

Abre `index.html` en el navegador para escoger entre los tres sistemas.

| Archivo | Qué es |
| --- | --- |
| `farmacia.html` | Azullab Farmacia: caja con factura por imprenta digital, productos, inventario por lote y vencimiento, compras, clientes, fiscal, ganancias y gastos, bancos, sin conexión, usuarios y permisos editables, configuración, fase 2 y el módulo de nómina aparte |
| `laboratorio.html` | Azullab Laboratorio Clínico: atención sin cita, ficha completa del paciente, datos de la visita, toma de muestras con etiquetas, carga y validación de resultados, informe firmado con QR, reactivos, caja y fase 2 |
| `crossfit.html` | Azullab CrossFit (regalo para el grupo): pizarra del día que escribe el coach con ejemplo visual de cada movimiento, app del socio en el teléfono (ve la rutina, reserva clase, anota su resultado), registro de socios, membresías con aviso de vencimiento, cobros y entrada con cédula. Abre `crossfit.html#socio` para entrar directo a la vista del socio |
| `papel-fiscal/` | Sistema de diseño de Cuadre: tokens (colores, letras) y componentes CSS |
| `seniat/` | Guías fiscales (SENIAT, imprenta digital, retenciones, trabajo sin internet) y libros de compras, ventas e inventario en Excel |
| `recipes/` | Base de datos de récipes (documento y SQL para Supabase) |
| `nomina/` | Módulo de nómina: horas extra, bono nocturno, liquidaciones, aumentos, archivo TXT para el banco y parámetros de ley |
| `propuesta/` | Propuesta económica de la farmacia: precios, mensualidad, forma de pago y condiciones del servicio |

Cada HTML es un solo archivo: estilos, datos de muestra y lógica van adentro. No necesita servidor; solo hace falta internet para cargar las letras.

Ningún dato de pacientes, clientes o ventas es real.
