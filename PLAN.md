# De maqueta a sistema real · Grupo Azullab

Hoy `farmacia.html`, `laboratorio.html` y `crossfit.html` son maquetas: los datos son de muestra y se pierden al recargar. El plan es dejar las mismas pantallas, pero guardando todo en **Supabase** (Postgres en la nube, con login y permisos por rol).

## Pasos

| # | Paso | Estado |
| --- | --- | --- |
| 1 | **Base común**: empresas (un RIF cada una), usuarios y roles, tasa BCV, facturas y notas con numeración correlativa, IVA e IGTF calculados por la base, libro de ventas y auditoría | ✅ Hecho y probado (`supabase/migrations/0001`, 47 pruebas) |
| 2 | Tasa BCV automática cada hora | ✅ Función escrita (`supabase/functions/tasa-bcv`), falta subirla |
| 3 | Crear el proyecto Supabase y subir la base | ⏳ Necesita tu cuenta |
| 4 | Conexión común para los tres HTML: login real, modo sin conexión (cola en el equipo que se sube al volver internet) | Siguiente |
| 5 | **Farmacia**: productos, lotes y vencimientos, caja que factura de verdad, compras, clientes, inventario, cierre de caja; récipes y controlados (ya hay SQL en `recipes/`) | |
| 6 | **Laboratorio**: pacientes, catálogo de exámenes, órdenes, muestras, resultados, informe con QR | |
| 7 | **CrossFit**: socios, planes y membresías, cobros, pizarra del día, app del socio | |
| 8 | **Imprenta digital**: conectar la factura con el proveedor autorizado por el SENIAT (número de control) | Bloqueado: hay que escoger proveedor |
| 9 | Nómina, bancos, reportes y tablero del dueño | |
| 10 | Publicar (dominio, HTTPS), cargar datos reales, capacitar y arrancar en paralelo con el sistema actual | |

## Lo que necesito de ti

1. **Supabase**: crea una cuenta en supabase.com y un proyecto (región São Paulo o us-east). Pásame la *Project URL* y la *anon key* (Settings → API). La *service_role key* **no** la pegues en el chat: ponla tú en los secretos del proyecto.
2. **Imprenta digital**: con qué empresa autorizada por el SENIAT van a facturar (cada RIF necesita su providencia). Sin esto, las facturas quedan como "pendiente de imprenta".
3. **Datos fiscales reales** de cada empresa: razón social, RIF, domicilio fiscal, teléfono y el rango del talonario de contingencia. (Faltan los RIF de la farmacia y del CrossFit.)
4. **Usuarios iniciales**: nombre, correo y rol de cada persona en cada negocio.
5. **Datos para cargar**: catálogo de productos con costo y existencia (Excel), lista de exámenes y precios del laboratorio, planes del CrossFit.
6. **Confirmar con el contador**: alícuotas por producto, IGTF y si el laboratorio es exento.
7. **Fecha de entrega** pactada con el cliente y cuál negocio arranca primero.

## Cómo probar la base en local

```bash
PGHOST=/tmp/pg PGPORT=5433 PGUSER=postgres supabase/tests/correr.sh
```
