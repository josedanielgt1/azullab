# Agente de la impresora fiscal (farmacia)

La caja de Cuadre es una página web y no puede hablar directo con una impresora por USB o serial. Por eso, en la computadora de la caja corre un programa pequeño, el **agente**. El agente recibe la factura por `http://127.0.0.1:7123`, la manda a la impresora con la librería del fabricante (por ejemplo la de The Factory HKA) y devuelve lo que respondió la máquina.

**Cuadre nunca numera una factura fiscal.** El número sale de la memoria fiscal y la base solo lo guarda (`registrar_maquina`).

## Cómo se activa

- Lo activa el dueño en **Módulo fiscal → Configurar la impresora**, con el medio «Máquina fiscal», la marca, el modelo, el **número de registro** (el que va junto al logo MH) y la dirección del agente.
- Si en el agente se escribe `simulada`, el mismo navegador imita la impresora para practicar. Esos números empiezan en **900000001**, el ticket dice «NO ES UNA FACTURA FISCAL» y Módulo fiscal lo avisa arriba.

## Protocolo

Todo va en JSON. Los montos van en bolívares con dos decimales.

| Ruta | Método | Para qué |
| --- | --- | --- |
| `/estado` | GET | Saber si la impresora responde |
| `/documento` | POST | Imprimir una factura, nota de crédito o nota de débito |
| `/reporte-x` | POST | Imprimir el Reporte X (lectura sin cierre) |
| `/reporte-z` | POST | Imprimir el Reporte Z (cierre del día) |

### `GET /estado`

```json
{"ok": true, "registro": "Z7C0012345", "modelo": "HKA80", "memoria": "4 % usada"}
```

### `POST /documento`

Lo que manda la caja:

```json
{
  "id": "uuid del documento en Cuadre",
  "tipo": "FAC",
  "fecha": "2026-11-05T14:10:00-04:00",
  "cliente": {"rif": "V-12345678", "nombre": "María Pérez", "dir": null, "tel": null},
  "lineas": [{"descripcion": "Losartán 50 mg · Caja x 30", "cantidad": 2, "precio": 300.00, "alicuota": "E"}],
  "pagos": [{"metodo": "Pago móvil", "monto": 600.00}],
  "totales": {"exento": 600.00, "base_general": 0, "iva_general": 0, "base_reducida": 0, "iva_reducida": 0, "igtf": 0, "total": 600.00},
  "tasa": 100.0, "total_usd": 6.00,
  "motivo": null,
  "afecta": null,
  "pie": ["REF. USD 6,00", "TASA BCV 100,00"]
}
```

- `tipo`: `FAC`, `NC` o `ND`. `alicuota`: `E` (exento), `G` (16 %) o `R` (8 %). `precio` es el precio unitario **sin IVA**.
- En una nota, `afecta` trae la factura que corrige: `{"numero": 1501, "control": null, "fecha": "...", "registro": "Z7C0012345"}`. Si esa factura salió del talonario, en `control` viene su número de control, y `motivo` trae el motivo de la nota.
- `pie` son líneas de texto para el final del ticket (la referencia en dólares y la tasa BCV).

Lo que responde el agente:

```json
{"ok": true, "numero": 1501, "registro": "Z7C0012345", "fecha": "2026-11-05T14:10:03-04:00"}
```

o, si la máquina no imprimió:

```json
{"ok": false, "error": "Sin papel"}
```

- **No debe imprimir dos veces el mismo `id`.** Si recibe un `id` que ya imprimió, devuelve el mismo número sin imprimir. Esto evita duplicados cuando la caja reintenta.
- El `error` lo lee el cajero tal cual: tiene que estar en español y ser claro («Sin papel», «Tapa abierta», «Error de memoria fiscal»).

### `POST /reporte-x` y `POST /reporte-z`

```json
{
  "ok": true, "registro": "Z7C0012345", "numero": 87,
  "fac_desde": 1501, "fac_hasta": 1530, "cant_fac": 30,
  "nc_desde": 1, "nc_hasta": 1, "cant_nc": 1,
  "nd_desde": null, "nd_hasta": null, "cant_nd": 0,
  "exento": 8123.40, "base_general": 2100.00, "iva_general": 336.00,
  "base_reducida": 0, "iva_reducida": 0,
  "total": 10259.40,
  "texto": "texto del reporte, opcional, para mostrarlo en pantalla"
}
```

- `numero` solo en el Z. `total` es **neto**: facturas más notas de débito menos notas de crédito.
- La base guarda el Z, liga las facturas de esos rangos y lo compara con lo suyo («Cuadra» o «Revisar»). Se permite **un Z por día**.

## Requisitos del agente

- Escucha **solo en 127.0.0.1** (nunca en la red).
- CORS: responde `OPTIONS` y cada respuesta con `Access-Control-Allow-Origin: https://josedanielgt1.github.io`, `Access-Control-Allow-Headers: content-type`, `Access-Control-Allow-Methods: GET, POST` y `Access-Control-Allow-Private-Network: true` (Chrome lo pide para que una página de internet hable con la computadora local).
- Arranca solo con Windows y se reinicia si se cae.
- Guarda un registro de lo que imprimió (fecha, `id`, número y respuesta de la máquina).
- Con la impresora apagada o sin papel, responde `ok: false` en menos de 30 segundos. La caja corta a los 45.

## Sin internet

La impresora va por cable, así que sin internet **sigue facturando por la máquina**. La venta queda en el equipo con su número fiscal y sube sola al volver la conexión (`vender_impresa`), con la fecha y la tasa de cuando se imprimió. El Reporte Z también se puede hacer sin internet: queda guardado y sube después.

El talonario de imprenta autorizada se usa **solo si la máquina está dañada**. Ese número queda anotado en el libro de control de la máquina.

## Pendiente

- Escribir el agente para el modelo que compre la farmacia, con la librería del fabricante. Para probarlo hace falta la impresora conectada.
- Confirmar con el distribuidor si el modelo emite notas de débito.
