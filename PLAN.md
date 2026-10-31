# De maqueta a sistema real · Grupo Azullab

**Entrega: sábado 21 de noviembre de 2026.**

Hoy `farmacia.html`, `laboratorio.html` y `crossfit.html` son maquetas: los datos son de muestra y se pierden al recargar. El plan es dejar las mismas pantallas, pero guardando todo en **Supabase** (Postgres en la nube, con login y permisos por rol).

## Pasos

| # | Paso | Estado |
| --- | --- | --- |
| 1 | **Base común**: empresas (un RIF cada una), usuarios y roles, tasa BCV, facturas y notas con numeración correlativa, IVA e IGTF calculados por la base, libro de ventas y auditoría | ✅ Hecho y probado (`supabase/migrations/0001`, 47 pruebas) |
| 2 | Tasa BCV automática cada hora | ✅ Función escrita (`supabase/functions/tasa-bcv`), falta subirla |
| 3 | Crear el proyecto Supabase, conectar GitHub y crear el primer usuario (el dueño) | ⏳ En curso |
| 4 | Entrada con correo y clave: el sistema sabe quién es y abre según su rol, sin escogerlo. Sesión guardada en el equipo. Librería de Supabase dentro del repo para abrir sin internet | ✅ Hecho y probado en el navegador (22 pruebas) |
| 5 | **Farmacia**: productos, lotes y vencimientos, caja que factura de verdad, compras, clientes, inventario, cierre de caja; récipes y controlados (ya hay SQL en `recipes/`) | |
| 6 | **Laboratorio**: pacientes, catálogo de exámenes, órdenes, muestras, resultados, informe con QR | |
| 7 | **CrossFit**: socios, planes y membresías, cobros, pizarra del día, app del socio | |
| 8 | **Imprenta digital**: conectar la factura con el proveedor autorizado por el SENIAT (número de control) | Bloqueado: hay que escoger proveedor |
| 9 | Nómina, bancos, reportes y tablero del dueño | |
| 10 | Publicar (dominio, HTTPS), cargar datos reales, capacitar y arrancar en paralelo con el sistema actual | |

## Decisiones tomadas

- **Base de datos**: Supabase, conectado a este repositorio de GitHub.
- **Usuarios**: al instalar hay uno solo, el dueño (el primer usuario que se crea). Él crea los demás y les da su rol desde Usuarios.
- **Datos fiscales** (RIF, razón social, domicilio): se editan en Configuración. Hasta que el dueño los confirme, ese negocio no factura.
- **Catálogos** (productos, exámenes, planes): vacíos; se llenan al instalar.
- **Imprenta digital**: en espera. Mientras tanto las facturas quedan "pendiente de imprenta".

## Calendario hasta el 21 de noviembre

| Semana | Qué |
| --- | --- |
| 31 oct – 7 nov | Supabase en línea, usuarios y roles desde la pantalla, configuración fiscal editable, farmacia: productos, inventario y caja reales |
| 8 – 14 nov | Farmacia: compras, clientes, cierre, libros. Laboratorio: pacientes, órdenes, muestras, resultados, informe |
| 15 – 21 nov | CrossFit, modo sin conexión, quitar todos los datos de muestra, pruebas completas, publicación e instalación |

## Cómo probar la base en local

```bash
# base de datos (60 pruebas)
PGHOST=/tmp/pg PGPORT=5433 PGUSER=postgres supabase/tests/correr.sh
```
