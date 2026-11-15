# De maqueta a sistema real · Grupo Azullab

**Entrega: sábado 21 de noviembre de 2026** (con revisión del dueño antes).

Las pantallas de `farmacia.html`, `laboratorio.html` y `crossfit.html` son las mismas de la maqueta, pero ahora guardan en **Supabase** (proyecto `azullab`): se entra con correo y clave, cada uno ve lo de su rol y la base hace cumplir las reglas fiscales y de inventario.

## Qué ya es real

| Parte | Qué hace | Estado |
| --- | --- | --- |
| Entrada | Correo y clave; el sistema abre según el rol; sesión guardada; «Olvidé mi clave» | ✅ (la recuperación necesita GitHub Pages, ver abajo) |
| Usuarios | Equipo de cada negocio, nuevo usuario, dar acceso por correo, cambiar rol, caja, nombre y clave, quitar acceso | ✅ («Nuevo usuario» necesita subir la función `usuarios`) |
| Datos fiscales | RIF, razón social, domicilio, contador (en la farmacia, sin imprenta ni talonario: factura solo por máquina fiscal) en Configuración; sin confirmarlos el negocio no factura | ✅ |
| Tasa BCV | La base la lee directo de bcv.org.ve (función `tasa-bcv`, cada 5 min de 3 a 8 p. m.); se usa apenas se publica (la del día siguiente incluida); las cajas abiertas la toman solas; el dueño puede escribirla a mano | ✅ |
| Facturas y notas | Número correlativo por RIF, IVA e IGTF calculados por la base, notas de crédito y débito, libro de ventas; nada se edita ni se borra | ✅ (número de control: espera la imprenta) |
| **Farmacia** | Catálogo (vacío al instalar), códigos únicos, compras por lote, venta que factura y descuenta el lote que vence antes, salidas, devoluciones a su lote, clientes | ✅ |
| **Laboratorio** | Catálogo vacío con opción de cargar el catálogo base, pacientes, médicos, orden con su factura (L-0001), toma, resultados, validación solo del bioanalista, entrega, anulación con nota de crédito | ✅ |
| **CrossFit** | Planes, productos y horario que arma el dueño, socios, cobro con IVA 16 % que corre el vencimiento, entrada con cédula, reservas, pizarra del día | ✅ |
| Farmacia: carga inicial | Lo que ya está en los anaqueles entra sin factura (migración 0026): desde una hoja de Excel o CSV o a mano, por lote; no va al Libro de Compras ni deja deuda, y en el registro del art. 177 sale como existencia inicial. El dueño la cierra al terminar | ✅ (falta aplicar la 0026 en producción) |
| Farmacia: vencimientos | El año se escribe completo en Compras; no se recibe mercancía vencida; en la caja lo vencido sale «fuera de venta» y no se selecciona; el dueño, gerente, regente o almacén corrigen un vencimiento mal escrito desde Inventario y lotes, con motivo y rastro (migración 0027) | ✅ (falta aplicar la 0027 en producción) |
| Farmacia: tasa de la factura de compra | En Compras se escribe la tasa que trae impresa la factura de la droguería (la del día anterior, la del euro…); el Libro de Compras sale en bolívares a esa tasa. Vacía, va con la BCV del día de la factura. También en la nota de crédito de la droguería (migración 0028) | ✅ (falta aplicar la 0028 en producción) |
| Farmacia: administración | Droguerías con RIF, factura de compra (número y control), Libro de Compras, cuentas por pagar y pagos, gastos, cuentas bancarias, configuración, fallas, cotizaciones, nómina (empleados y novedades), Ganancias y gastos con cifras reales, tablero con las ventas reales | ✅ |
| Farmacia: récipes y controlados | Récipes con número interno, médicos con MPPS, récipe especial sin repetir; la base no deja vender un controlado sin el récipe del paciente ni más de lo autorizado; el libro de controlados se llena solo con cada movimiento y cuadra con el inventario | ✅ |
| Farmacia: bancos, puntos y alertas | Cuentas y bancos con lo cobrado hoy, deuda con droguerías y Cashea guardado; Azul Puntos con los clientes reales; libro de ventas del módulo fiscal con las facturas; alertas de alergias que registra la regente y la caja frena sin ver el motivo | ✅ |
| Laboratorio: catálogo, reactivos e historial | Editor de exámenes (precio, tubo, parámetros, referencias por sexo, reactivo que gasta) y de perfiles; entrada y corrección de reactivos; al validar se descuenta el reactivo; historial del paciente con sus órdenes | ✅ |
| Farmacia: sin internet | Detecta sola el corte; la impresora fiscal sigue facturando por cable, guarda la venta en el equipo con su número fiscal y la sube sola al volver (`vender_impresa`). Sin internet y con la impresora dañada no se factura: se reintenta o se cancela la venta | ✅ |
| Farmacia: nómina | Empleados, novedades y pagos de cada quincena guardados; la quincena, el calendario de pagos y las liquidaciones usan la fecha de hoy. Recibos por WhatsApp (uno por uno, con el recibo escrito) e impresos; constancia de trabajo, cálculo del AR-I y finiquito para imprimir o guardar en PDF; datos del pago móvil que se copian; archivo del banco con la cuenta marcada «nómina» y el RIF real; aumentos que entran el día que les toca. El acceso al sistema de un empleado se da en Usuarios | ✅ |
| Los tres: calendario fiscal y forma 30 | Calendario fiscal del mes en curso; sin excedente de crédito fiscal, libro de compras ni retenciones de muestra | ✅ |
| Laboratorio y CrossFit: libro de compras | «Registrar factura de compra» en Libros y declaración: proveedor, RIF, número, control, exento, base gravable y retención de ISLR; entra al Libro de Compras y al comprobante de retención | ✅ |
| Los tres: declaración de IVA | En Datos fiscales, el excedente de crédito fiscal del mes anterior y la última declaración (los da el contador) | ✅ |
| Laboratorio y CrossFit: sin internet | La orden del laboratorio y el cobro de membresía se hacen con el talonario de contingencia, quedan en el equipo (también el paciente o socio nuevo) y suben solos al volver | ✅ |
| CrossFit: app del socio | El dueño le da acceso desde la ficha del socio (correo y clave); el socio ve la pizarra, reserva su clase y anota su resultado; no ve facturas, cobros, otros socios, al equipo, ni la lista de clientes y proveedores (migración 0025), y no factura | ✅ (necesita la función `usuarios`) |
| Los tres: app instalable y PIN | Se instala en la computadora («Instalar Azullab…»), abre sin internet; en un equipo registrado cada persona entra con su PIN, con o sin internet (5 errores bloquean, 7 días sin conexión vencen) | ✅ (necesita GitHub Pages: https) |
| Los tres: respaldo sin internet | Franja de aviso mientras haya algo sin subir; copia en una carpeta del equipo; «Recuperar desde un archivo de respaldo» sin repetir nada | ✅ |
| Los tres: panel del grupo | El dueño ve las ventas reales del mes de los tres negocios | ✅ |

Pruebas: **480 de base de datos** (`supabase/tests/correr.sh`) y **355 de navegador** (`tests/navegador/correr.sh`), incluidas las de ataque (`tests/navegador/seguridad.test.js`) y la que recorre todas las pantallas con cada rol buscando textos o nombres de la maqueta (`tests/navegador/textos.test.js`).

## Qué todavía muestra datos de muestra

| Negocio | Módulo | Qué falta |
| --- | --- | --- |
| Farmacia | Diferencial cambiario | Necesita los saldos diarios del banco (hoy queda vacío) |
| Farmacia | Recordatorios de tratamientos continuos por WhatsApp | Fase 2 |
| Los tres | Fase 2 (tienda web, sucursales, Azul Puntos; portal, equipos, convenios, calidad y grupo del laboratorio) | Guardada en los archivos y fuera del menú; se activa con `FASE2 = true` en `js/cuadre-comun.js` |
| Farmacia | Cuentas y bancos | Conciliación con el estado de cuenta: necesita los movimientos del banco |
| Los tres | Páginas «Alcance de la propuesta», «Alcance y regalo», «Fase 2» | Decidir si se quitan para el cliente |
| Farmacia | Máquina fiscal | Hecho en la base y en la caja (migración 0023): factura, notas, falla: reintentar o dejar pendiente (anotada en el libro de la máquina; sin talonario), sin internet, Reporte X y Z, libro de ventas por Z y libro de control. Falta el **agente** para el modelo que compren (protocolo en `docs/agente-maquina-fiscal.md`); mientras, se practica con la impresora «simulada» |
| Farmacia | Registro de inventario (art. 177) | Real desde la migración 0024: sale de los movimientos de la base (antes eran cifras de muestra). Confirmar la presentación con el contador |
| Farmacia | Notas de crédito de droguerías | En Proveedores y pagos (migración 0024): restan en el Libro de Compras y en la deuda, y lo devuelto sale de sus lotes |
| Laboratorio y CrossFit | Medio de facturación | Siguen con imprenta digital (se escoge por empresa). Conectar al proveedor cuando lo escojan |

> **Nota · The Factory HKA.** Todo indica que la imprenta digital será The Factory HKA, y que ellos también llevarían la parte contable (libros, declaración de IVA, retenciones). Si se confirma, más adelante se pueden quitar o simplificar en Cuadre: Libro de Compras y de Ventas, forma 30 y calendario fiscal, comprobantes de retención de ISLR, checklist del SENIAT y Ganancias y gastos. Por ahora **no se quita nada**: queda anotado para decidirlo con el contador.

Guía para instalar y revisar: `INSTALACION.md`.

## Lo que hace falta de ti

Al 10 nov: en producción están las migraciones hasta la 0025 y la función `usuarios` al día. **Faltan la 0026** (carga inicial) **y la 0027** (vencimientos): pegar `supabase/pendiente_sql_editor.sql` en el SQL Editor.

1. **Protección de claves filtradas**: solo existe en el plan Pro de Supabase (Authentication → Sign In / Providers → Email → «Prevent use of leaked passwords»). En el plan gratis queda el mínimo de 8 caracteres con mayúsculas, minúsculas y números. Activarla solo si pasan a Pro.
2. **GitHub Pages** (para «Olvidé mi clave» y para entrar desde cualquier equipo): Settings → Pages → rama `main`, carpeta raíz. En Supabase → Authentication → URL Configuration: Site URL `https://josedanielgt1.github.io/azullab/` y en Redirect URLs `https://josedanielgt1.github.io/azullab/**`.
3. **Impresora fiscal de la farmacia**: Módulo fiscal → Configurar la impresora (marca, modelo, registro MH y agente). Sin eso la farmacia no factura: no tiene imprenta digital ni talonario.
4. **Imprenta digital**: solo laboratorio y CrossFit, cuando la escojan.

## Decisiones tomadas

- **Base de datos**: Supabase. Las migraciones están en `supabase/migrations`; para el SQL Editor se arma un solo archivo con `supabase/armar_sql_editor.sh`.
- **Usuarios**: el primer usuario creado es el dueño de los tres negocios. Él crea a los demás y les da su rol.
- **Datos fiscales**: editables; sin confirmarlos no se factura.
- **Catálogos**: vacíos al instalar (en el laboratorio, con la opción de cargar el catálogo base para ajustarlo).
- **Socio nuevo del CrossFit**: queda vencido hasta que se le cobre.
- **Farmacia por máquina fiscal** (5 nov 2026). El medio se escoge por empresa en `empresas.medio_factura`; el laboratorio y el CrossFit siguen con imprenta digital.
- **Imprenta digital** (laboratorio y CrossFit): en espera; las facturas quedan «pendiente de imprenta».
- **IGTF**: los tres negocios son contribuyentes ordinarios y no lo cobran. Si el SENIAT designa especial a alguno, se pone `igtf = 3` en su fila de `empresas`.

## Cómo probar en local

```bash
PGHOST=/tmp/pg PGPORT=5433 PGUSER=postgres supabase/tests/correr.sh
```

```bash
tests/navegador/correr.sh
```
