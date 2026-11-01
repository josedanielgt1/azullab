# De maqueta a sistema real · Grupo Azullab

**Entrega: sábado 21 de noviembre de 2026** (con revisión del dueño antes).

Las pantallas de `farmacia.html`, `laboratorio.html` y `crossfit.html` son las mismas de la maqueta, pero ahora guardan en **Supabase** (proyecto `azullab`): se entra con correo y clave, cada uno ve lo de su rol y la base hace cumplir las reglas fiscales y de inventario.

## Qué ya es real

| Parte | Qué hace | Estado |
| --- | --- | --- |
| Entrada | Correo y clave; el sistema abre según el rol; sesión guardada; «Olvidé mi clave» | ✅ (la recuperación necesita GitHub Pages, ver abajo) |
| Usuarios | Equipo de cada negocio, nuevo usuario, dar acceso por correo, cambiar rol, caja, nombre y clave, quitar acceso | ✅ («Nuevo usuario» necesita subir la función `usuarios`) |
| Datos fiscales | RIF, razón social, domicilio, imprenta, talonario y contador en Configuración; sin confirmarlos el negocio no factura | ✅ |
| Tasa BCV | Se lee de la base; si falta la de hoy, la carga el dueño al entrar o la escribe a mano | ✅ |
| Facturas y notas | Número correlativo por RIF, IVA e IGTF calculados por la base, notas de crédito y débito, libro de ventas; nada se edita ni se borra | ✅ (número de control: espera la imprenta) |
| **Farmacia** | Catálogo (vacío al instalar), códigos únicos, compras por lote, venta que factura y descuenta el lote que vence antes, salidas, devoluciones a su lote, clientes | ✅ |
| **Laboratorio** | Catálogo vacío con opción de cargar el catálogo base, pacientes, médicos, orden con su factura (L-0001), toma, resultados, validación solo del bioanalista, entrega, anulación con nota de crédito | ✅ |
| **CrossFit** | Planes, productos y horario que arma el dueño, socios, cobro con IVA 16 % que corre el vencimiento, entrada con cédula, reservas, pizarra del día | ✅ |
| Farmacia: administración | Droguerías con RIF, factura de compra (número y control), Libro de Compras, cuentas por pagar y pagos, gastos, cuentas bancarias, configuración, fallas, cotizaciones, nómina (empleados y novedades), Ganancias y gastos con cifras reales, tablero con las ventas reales | ✅ |
| Farmacia: récipes y controlados | Récipes con número interno, médicos con MPPS, récipe especial sin repetir; la base no deja vender un controlado sin el récipe del paciente ni más de lo autorizado; el libro de controlados se llena solo con cada movimiento y cuadra con el inventario | ✅ |
| Farmacia: bancos, puntos y alertas | Cuentas y bancos con lo cobrado hoy, deuda con droguerías y Cashea guardado; Azul Puntos con los clientes reales; libro de ventas del módulo fiscal con las facturas; alertas de alergias que registra la regente y la caja frena sin ver el motivo | ✅ |
| Laboratorio: catálogo, reactivos e historial | Editor de exámenes (precio, tubo, parámetros, referencias por sexo, reactivo que gasta) y de perfiles; entrada y corrección de reactivos; al validar se descuenta el reactivo; historial del paciente con sus órdenes | ✅ |
| Farmacia: sin internet | Detecta sola el corte; vende con el talonario de contingencia (número y control), guarda la venta en el equipo y la sube sola al volver con su fecha y la tasa de ese día; abre con la copia local del catálogo; publicado en https queda instalado en el equipo | ✅ |
| Farmacia: nómina | Empleados, novedades y pagos de cada quincena guardados; la quincena, el calendario de pagos y las liquidaciones usan la fecha de hoy | ✅ |
| Los tres: calendario fiscal y forma 30 | Calendario fiscal del mes en curso; sin excedente de crédito fiscal, libro de compras ni retenciones de muestra | ✅ |
| Laboratorio y CrossFit: libro de compras | «Registrar factura de compra» en Libros y declaración: proveedor, RIF, número, control, exento, base gravable y retención de ISLR; entra al Libro de Compras y al comprobante de retención | ✅ |
| Los tres: declaración de IVA | En Datos fiscales, el excedente de crédito fiscal del mes anterior y la última declaración (los da el contador) | ✅ |
| Los tres: panel del grupo | El dueño ve las ventas reales del mes de los tres negocios | ✅ |

Pruebas: **235 de base de datos** (`supabase/tests/correr.sh`) y **150 de navegador** (`tests/navegador/correr.sh`).

## Qué todavía muestra datos de muestra

| Negocio | Módulo | Qué falta |
| --- | --- | --- |
| Farmacia | Diferencial cambiario | Necesita los saldos diarios del banco (hoy queda vacío) |
| Farmacia | Recordatorios de tratamientos continuos por WhatsApp | Fase 2 |
| Farmacia | Cotizaciones, fallas, Cashea, Azul Puntos, tienda web, sucursales | Guardar o apagar hasta la fase 2 |
| Farmacia | Tienda web y sucursales | Pantallas de muestra de la fase 2, marcadas como tal |
| Farmacia | Azul Puntos | Los puntos ya se suman; falta el canje en la caja (fase 2) |
| Farmacia | Cuentas y bancos | Conciliación con el estado de cuenta y diferencial cambiario: necesitan los movimientos del banco |
| Laboratorio | Portal, equipos, convenios, calidad y grupo | Pantallas de muestra de la fase 2, marcadas como tal |
| Los tres | Páginas «Alcance de la propuesta», «Alcance y regalo», «Fase 2» | Decidir si se quitan para el cliente |
| Laboratorio y CrossFit | Trabajo sin internet | La farmacia ya vende sin internet; en el laboratorio y el CrossFit todavía hace falta conexión para cobrar |
| CrossFit | App del socio | Vuelve cuando los socios tengan su usuario |

## Lo que hace falta de ti

1. **Pegar en el SQL Editor** `supabase/pendiente_sql_editor.sql` (migraciones 0003 a 0014). Una sola vez, completo, y Run.
2. **Subir la función `usuarios`**: Supabase → Edge Functions → Deploy a new function → Via Editor, nombre `usuarios`, pegar `supabase/functions/usuarios/index.ts` y Deploy. Sin esto, los usuarios nuevos se crean en Authentication y se les da acceso con «Dar acceso».
3. **GitHub Pages** (para «Olvidé mi clave» y para entrar desde cualquier equipo): Settings → Pages → rama `claude/inspiring-pascal-ljb7rr`, carpeta raíz. En Supabase → Authentication → URL Configuration: Site URL `https://josedanielgt1.github.io/azullab/` y en Redirect URLs `https://josedanielgt1.github.io/azullab/**`.
4. **Talonario de contingencia**: en Configuración → Datos fiscales, el rango del talonario (desde y hasta). Sin eso, la farmacia no puede vender sin internet.
5. **Imprenta digital**: cuando la escojan, se conecta para el número de control.

## Decisiones tomadas

- **Base de datos**: Supabase. Las migraciones están en `supabase/migrations`; para el SQL Editor se arma un solo archivo con `supabase/armar_sql_editor.sh`.
- **Usuarios**: el primer usuario creado es el dueño de los tres negocios. Él crea a los demás y les da su rol.
- **Datos fiscales**: editables; sin confirmarlos no se factura.
- **Catálogos**: vacíos al instalar (en el laboratorio, con la opción de cargar el catálogo base para ajustarlo).
- **Socio nuevo del CrossFit**: queda vencido hasta que se le cobre.
- **Imprenta digital**: en espera; las facturas quedan «pendiente de imprenta».

## Cómo probar en local

```bash
PGHOST=/tmp/pg PGPORT=5433 PGUSER=postgres supabase/tests/correr.sh
```

```bash
tests/navegador/correr.sh
```
