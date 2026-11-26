# Agente de la impresora fiscal (Cuadre · farmacia)

Programa pequeño que va en la **computadora de la caja**. La caja de Cuadre es una página web y no puede hablar con el puerto USB; el agente sí. Escucha solo en `http://127.0.0.1:7123` (nunca en la red) y le pasa a la impresora fiscal lo que pide la caja, con el **protocolo directo de The Factory HKA** (Aclas PP9 Plus, HKA80 y modelos parecidos). Contrato con la caja: `docs/agente-maquina-fiscal.md`.

- Un solo archivo, `CuadreAgente.exe`, sin instalar nada más. Sirve en Windows de 32 y 64 bits.
- No usa la DLL del fabricante: arma las tramas según el «Manual de Protocolos y Comandos V8.5.0».
- **Cuadre nunca numera**: el número de factura sale de la memoria fiscal (status S1).

## Instalar en la computadora de la caja

1. Copia `CuadreAgente.exe` a la computadora (de un pendrive o de donde lo bajes).
2. Doble clic. Si Windows avisa «Windows protegió su PC», dale **Más información → Ejecutar de todas formas** (el programa no está firmado).
3. Se copia solo a `%LOCALAPPDATA%\CuadreAgente`, queda arrancando con Windows y abre su página en el navegador: `http://127.0.0.1:7123/`.
4. Conecta la impresora por USB y enciéndela. En la página del agente dale **Revisar de nuevo**: tiene que decir «Impresora lista» con el modelo, el registro y el RIF.
5. En Cuadre (farmacia, como dueño): **Módulo fiscal → Configurar la impresora** → marca Aclas, modelo PP9 Plus, el número de registro que mostró el agente, y agente `http://127.0.0.1:7123`. Si Chrome pregunta si la página puede acceder a la red local, **Permitir**.

Para actualizarlo: doble clic en el `.exe` nuevo; reemplaza al anterior solo. Para quitar el arranque con Windows: `CuadreAgente.exe -desinstalar`.

## La página del agente (`http://127.0.0.1:7123/`)

- **Revisar de nuevo**: estado de la impresora (lista, sin papel, error fiscal…), flags y memoria.
- **Imprimir programación**: la impresora imprime sus tasas, medios de pago y flags (no es fiscal).
- **Programar medios de pago**: graba en la impresora los nombres 01 a 06 (ver abajo). Puede pedir un Reporte Z antes.
- **Diagnóstico**: lee la impresora y muestra sus respuestas crudas. Si algo no cuadra, copia ese texto y mándaselo a Cuadre. También queda en `%LOCALAPPDATA%\CuadreAgente\diagnostico.txt`.

## Configuración (`%LOCALAPPDATA%\CuadreAgente\agente.json`)

Se crea sola. Lo normal es no tocarla.

| Campo | Por defecto | Qué es |
| --- | --- | --- |
| `puerto` | `auto` | `auto` busca la impresora en todos los COM; o fijo, por ejemplo `COM3` |
| `paridad` | `auto` | `auto` prueba **par** (manual de protocolos) y después **ninguna** (manual de usuario) |
| `control_flujo` | `false` | RTS/CTS por hardware |
| `origenes` | `https://josedanielgt1.github.io` | Páginas que pueden usar el agente |
| `flag21`, `flag50` | `30`, `0` | Solo si la impresora no deja leer sus flags (S3); si los deja, manda lo que ella diga |
| `medios` | ver abajo | Número de medio de pago en la impresora para cada forma de pago de Cuadre |

Medios de pago (moneda nacional, 01 a 19, sin IGTF):

| N.º | Nombre | Formas de pago de Cuadre |
| --- | --- | --- |
| 01 | EFECTIVO BS | Efectivo Bs (y lo que no reconozca) |
| 02 | EFECTIVO USD | Efectivo USD, Efectivo $, Divisas |
| 03 | PAGO MOVIL | Pago móvil |
| 04 | PUNTO VENTA | Punto de venta |
| 05 | TRANSFERENCIA | Transferencia |
| 06 | ZELLE | Zelle |

## Configuración que debe tener la impresora

- Flags **21=30** (precios 14 + 2), **50=00** (sin IGTF: contribuyente ordinario), **63=01** (respuestas ampliadas). El agente lee los flags al conectarse y se adapta al 21 y al 50.
- Tasas 16 % y 8 %. Fiscalizada con el RIF real de la farmacia.

## Cómo imprime una factura

1. Revisa el estado. Si quedó un documento abierto (se fue la luz), lo anula.
2. Lee S1 (último número), manda cliente (RIF y razón social; al consumidor final no), renglones, y el pie (referencia en USD y tasa BCV) como comentarios.
3. Lee S2 y compara el total de la impresora con el de Cuadre. Si difieren en más de Bs 0,05, **anula y no imprime** (casi siempre son las tasas de IVA mal programadas).
4. Pagos: los primeros como pagos parciales; el último, si es mayor que lo que falta, como pago parcial (la impresora calcula el cambio), y si no, como pago directo (paga lo exacto). Con el flag 50 en 01 cierra con el comando 199.
5. Espera a que termine, lee S1 y devuelve el número nuevo. Guarda el `id` en `impresos.json` para no imprimir dos veces la misma venta.

Notas de crédito: mandan factura afectada (`iF*`), su fecha (`iD*`), el registro de la máquina (`iI*`), RIF y razón social, como exige el manual.

## Lo que hay que confirmar con la impresora real

El agente está probado contra una impresora simulada hecha según el manual, y contra la caja de Cuadre de verdad (`tests/navegador/agente.test.js`). Con la impresora enfrente hay que confirmar, con **Diagnóstico**:

- la paridad del puerto (el agente prueba las dos y se queda con la que responde);
- las posiciones de los campos de S1, S2, S3 y U0X (el agente lee con separadores 0x0A si vienen, o por los anchos del manual);
- el formato del número de factura afectada en las notas de crédito (`iF*` con 8 dígitos);
- cuánto tarda en imprimir (espera hasta 25 s una factura y 35 s el Reporte Z).

## Para programadores

```bash
cd agente
go test ./...                 # pruebas con la impresora simulada
go run . -puerto sim -dir /tmp/agente   # el agente con la impresora simulada, en http://127.0.0.1:7123
./compilar.sh                 # dist/CuadreAgente.exe (Windows, 32 bits)
```

Sin dependencias: solo la biblioteca estándar de Go. Archivos: `protocolo.go` (tramas, ACK/NAK, ENQ), `tramas.go` (formatos y lectura de S1/S2/S3/S5/SV/U0X), `impresora.go` (factura, notas, reportes), `servidor.go` (rutas, CORS, página), `sistema_windows.go` (puerto serial, instalación, supervisor), `simulador.go`.
