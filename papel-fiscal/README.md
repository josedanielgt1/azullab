Papel Fiscal es la forma de todos los sistemas de gestión que firma Cuadre: cajas, inventarios, nóminas, libros fiscales. Nace del papel con el que el comercio venezolano ya trabaja (la factura fiscal, el libro contable, la planilla del SENIAT, el sello húmedo) para que el sistema se sienta serio, contable y de aquí. La forma es siempre la nuestra; el color de acento es del cliente.

## La idea en una frase

Cada pantalla es una **hoja** dentro de una **carpeta**, se navega con **separadores** de archivador, los datos se llenan en **casillas**, las cifras se escriben a **máquina**, las tablas son **libros** y los estados se marcan con **sellos**.

## Voz y escritura

- Escribe como habla un encargado de negocio en Venezuela: claro, directo, de tú dentro del sistema ("Escanea el primer producto"), formal en los documentos que salen a terceros.
- Minúscula de oración en títulos, botones y etiquetas: "Libro de ventas", "Emitir factura fiscal". Las MAYÚSCULAS son solo para sellos, marcas y el texto de los tickets fiscales.
- Los botones dicen lo que pasa ("Cargar al inventario"); la confirmación repite el verbo ("Compra cargada: 4 productos").
- Los errores dicen qué falta y cómo se arregla: "Completa lote y vencimiento en 2 productos antes de cargar". Sin disculpas ni signos de exclamación.
- Sin emojis. Sin términos técnicos: "sin internet", no "offline"; "subir", no "sincronizar la cola".
- Vocabulario del comercio: caja, cuadre, cierre, Reporte Z, tasa BCV, pago móvil, droguería, lote, récipe, consumidor final.

## Números, fechas y dinero

- Formato venezolano siempre: punto de miles, coma decimal, dos decimales (`1.142,60`). Se escriben en la familia `maquina` con cifras tabulares, alineadas a la derecha en tablas.
- Moneda delante con espacio: `$ 3,80`, `Bs 3.351,14`. Todo monto en dólares lleva su equivalente en bolívares a la tasa BCV del día, y la tasa visible en la cabecera (componente Monto).
- Negativos entre paréntesis en `sello-rojo`: `(1.587,38)`.
- Fechas `dd-mm-aaaa` (`26-10-2026`) y horas de 24 h (`14:09`). Documentos con su número completo: `Factura 00001249`, `Reporte Z #0087`.
- Cédulas y RIF con su letra: `V-18.456.123`, `J-41203398-5`.

## Color

- `mesa` es el fondo de la aplicación; `hoja-alt` es el interior de la carpeta abierta; `hoja` es todo papel donde se lee o se escribe. Nunca pongas texto largo directo sobre `mesa`.
- Texto en `tinta` sobre `hoja`, `hoja-alt` y `mesa`; secundario en `tinta-2`; etiquetas, folios y metadatos en `tinta-3`.
- `renglon` para las líneas de las tablas y divisiones; `linea` para el borde de todo control (casillas, botones). `margen` solo para la doble línea roja del libro.
- Los cuatro colores de sello son estados y nada más: `sello-verde` pagado o vigente, `sello-rojo` vencido, anulado o faltante, `sello-ambar` pendiente o por vencer, `sello-violeta` registrado o recibido. Siempre van con palabra.
- `foco` es fijo: el anillo de teclado no cambia con el cliente.

### El color del cliente

El cliente aporta cuatro valores; todo lo demás es nuestro:

| Token | Qué es | Azullab Farmacia |
| --- | --- | --- |
| `acento` | su color, de relleno | `#3db2e8` (celeste) |
| `on-acento` | texto sobre su color | `#0b2340` (su celeste es claro: texto oscuro) |
| `acento-tinta` | su color como texto, 4.5:1 sobre `hoja` | `#0a6fa8` |
| `acento-suave` | su color muy claro, para fondos | `#e3f4fc` |

Mide el contraste antes de entregar: si el color del cliente es claro, `on-acento` es oscuro y `acento-tinta` es una versión más profunda del mismo tono. El acento se usa en la acción principal, el día actual de un gráfico, la casilla destacada y la fila seleccionada; no en títulos, no en fondos grandes.

## Tipografía

- Dos familias. `forma` (Archivo, de ancho variable) para todo lo que se lee; `maquina` (IBM Plex Mono) para todo lo que se cuenta: montos, cantidades, códigos, folios, fechas en tablas y tickets.
- Títulos de pantalla `titulo-hoja`; título de cada hoja `titulo-seccion`; texto `cuerpo`; nombres de producto o cliente `cuerpo-fuerte`; etiquetas de casilla y columnas `etiqueta`; ayudas `nota`.
- Los sellos usan `sello`: Archivo en ancho condensado (`font-stretch: 75%`), peso 800, mayúsculas.
- Cifra principal de un tablero en `cifra-grande`; cifras en tablas en `cifra`; folios y códigos en `cifra-chica`; tickets en `ticket`.

## Espacio, forma y profundidad

- Escala de 4px: `space-1` a `space-6`. Filas de libro y rayado al paso `alto-renglon` (40px). Controles de 44px o más: se usan con el dedo.
- Esquinas casi rectas: `radius-papel` (2px) en hojas, `radius-control` (4px) en controles, `radius-sello` en sellos, `radius-pestana` (8px) solo en separadores y pestañas.
- Sombras de papel: `sombra-hoja` en toda hoja; `sombra-pila` en documentos con páginas detrás; `sombra-flotante` solo en modales.
- Nada de degradados, ni tarjetas con borde de color a la izquierda, ni esquinas muy redondas.

## Estructura de pantalla

- Izquierda: Separadores sobre `mesa`, con el código de dos letras de cada sección. Derecha: la carpeta (`hoja-alt`) con la cabecera del documento (título de la pantalla, folio, tasa BCV, estado de la impresora y de la conexión) y las hojas.
- Cada hoja lleva **folio**: el código de su sección y su número (`Folio CJ-02`). Es la firma visual del sistema.
- En un tablero, la fila de cifras principales es una planilla de casillas unidas (Casilla) con la principal destacada.
- La venta en curso es un Ticket que se arma mientras se agregan productos.
- Muestra a cada rol solo lo suyo: el cajero ve su caja y su turno; el dueño ve todo.

## Movimiento

Solo dos movimientos, y los dos responden a una acción:

1. El **golpe del sello** (`is-estampando`, 0,24 s) cuando un estado cambia: pagado, recibido, anulado.
2. La **impresión del ticket** (`is-imprimiendo`, 1,6 s) cuando sale un documento fiscal.

Los botones se hunden 2px al pulsarlos. Nada más se mueve. Con `prefers-reduced-motion` no se anima nada.

## Iconografía

- Íconos de trazo, 18px, trazo 1,75, esquinas redondeadas, en SVG en línea con `currentColor` (compatibles con Lucide). Siempre acompañan una palabra; un ícono solo, sin texto, lleva `aria-label`.
- Sin emojis, ni ilustraciones, ni íconos de color.
- Este sistema no trae logo propio todavía: la marca Cuadre se escribe en `forma` peso 800. El logo del cliente va en la pantalla de entrada y en la cabecera de los documentos.

## Uso en código

Carga `tokens.css` y luego `components/bundle.css`; el segundo trae las fuentes de Google Fonts. Pon `data-theme="carbon"` en `<html>` para el tema oscuro (papel carbón). Para un cliente, redefine solo `--acento`, `--on-acento`, `--acento-tinta` y `--acento-suave` en `:root`, en ambos temas.
