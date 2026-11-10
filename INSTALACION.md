# Instalación y revisión · Grupo Azullab

Pasos para dejar los sistemas funcionando con la base real (Supabase, proyecto `azullab`) y una lista para revisarlos antes de entregar.

**Orden de instalación (decidido el 9 nov 2026):** la primera instalación, el 21 de noviembre, es **solo la farmacia**. El laboratorio y el CrossFit se instalan después, cada uno en su fecha, con estos mismos pasos del 4 y del 5.

## 1. Base de datos (una sola vez)

1. Supabase → **SQL Editor** → New query.
2. Si nunca pegaste nada: pega `supabase/instalar_en_sql_editor.sql` completo y dale **Run** (debe decir «Instalación lista: 3 empresas»).
3. Luego pega `supabase/pendiente_sql_editor.sql` completo y dale **Run** (debe decir «Listo: migraciones aplicadas»).
4. Para comprobar: **Table Editor** debe mostrar, entre otras, `productos`, `ordenes`, `socios`, `recipes`, `libro_controlados`.

En producción ya están todas hasta la 0025 (9 nov 2026); **falta aplicar la 0026** (carga inicial del inventario). Cada vez que haya migraciones nuevas, se arma el archivo con:

```bash
supabase/armar_sql_editor.sh 0026 > supabase/pendiente_sql_editor.sql   # el número es la primera migración que falta en producción
```

## 2. Usuarios

1. **Authentication → Sign In / Providers**: «Allow new users to sign up» apagado.
2. El primer usuario que se creó es el dueño de los tres negocios.
3. **Función `usuarios`** (para «Nuevo usuario» y «Dar acceso a la app» del socio): Edge Functions → Deploy a new function → Via Editor → nombre `usuarios` → pegar `supabase/functions/usuarios/index.ts` → Deploy. Si ya existe: Edge Functions → `usuarios` → Code. Copia siempre el archivo de GitHub o de un clon actualizado con `git pull`, nunca de una copia vieja.
4. Sin la función: crea el usuario en Authentication → Users → Add user, y en el sistema usa «Dar acceso» con su correo.

## 3. Publicar (para usarlo desde cualquier equipo y sin internet)

1. GitHub → Settings → Pages → Deploy from a branch → `main` → / (root).
2. Supabase → Authentication → URL Configuration: Site URL `https://josedanielgt1.github.io/azullab/` y Redirect URLs `https://josedanielgt1.github.io/azullab/**` (para «Olvidé mi clave»).
3. Publicado en https, cada equipo guarda el sistema y abre aunque no haya internet.

## 4. Primer día en cada negocio (lo hace el dueño)

Empieza por la farmacia; el laboratorio y el CrossFit, cuando les toque.

1. **Configuración → Datos fiscales**: razón social, RIF, domicilio, imprenta, talonario de contingencia (primer y último número), excedente del mes anterior. Marcar «confirmados» (sin eso no se factura).
   - Farmacia (máquina fiscal): número de registro de la máquina y el agente instalado en la PC de la caja (ver `docs/agente-maquina-fiscal.md`). Mientras no esté, se practica con la impresora «simulada».
2. **Tasa BCV**: se carga sola al entrar el dueño; si falla, «Tasa BCV» a mano.
3. **Usuarios**: crear al equipo con su rol (cajero, regente, almacén, atención, bioanalista, toma de muestras, coach). El acceso es por negocio: quien se crea en la farmacia solo entra a la farmacia. Al dueño real del Grupo se le crea en la farmacia y, cuando se instalen los otros, se le da acceso como dueño con «Dar acceso» en cada uno.
   - Antes de entregar, quitar los usuarios de prueba (por ejemplo «prueba») en Supabase → Authentication → Users.
4. **Catálogo**:
   - Farmacia: Proveedores (droguerías con RIF) y productos. Lo que ya está en los anaqueles entra por **Compras → Carga inicial** (dueño o gerente): desde una hoja de Excel o CSV (la plantilla se descarga ahí mismo; también sirve la hoja que tenga la farmacia, escogiendo qué columna es cada dato) o a mano, un renglón por lote. No es una compra: no lleva factura, no va al Libro de Compras y no deja deuda. Al terminar de contar, el dueño le da a «Cerrar la carga inicial» (no se vuelve a abrir desde el sistema); desde ahí la mercancía solo entra con su factura, por «Escanear factura».
   - Laboratorio: «Cargar el catálogo base» y ajustar precios, referencias y reactivo de cada examen.
   - CrossFit: Membresías y pagos → planes, productos y horario de clases.

## 5. Lista de revisión antes de entregar

Farmacia
- [ ] Carga inicial: subir la plantilla con dos productos y cargar uno a mano; la existencia sube, el Libro de Compras sigue vacío y en el registro de inventario sale como inicial.
- [ ] Crear un producto, recibir una compra con número y control de factura, verlo en el Libro de Compras.
- [ ] Vender con factura por la máquina fiscal: queda pendiente hasta que la impresora devuelve su número; la existencia baja del lote que vence primero; aparece en Mi turno y en el Libro de Ventas.
- [ ] Falla de la impresora: la factura sale del talonario y queda en el libro de control.
- [ ] Reporte Z del día: cuadra con la base.
- [ ] Devolución con nota de crédito: la mercancía vuelve al lote.
- [ ] Un controlado no se vende sin récipe especial del paciente; la venta queda en el libro de controlados.
- [ ] Sin internet (desconectar el wifi): vender con talonario; al volver, sube solo.
- [ ] Cajero: no ve ganancias, compras, récipes ni usuarios.

Laboratorio (en su instalación)
- [ ] Paciente nuevo, orden con factura, toma, resultados, validación (solo el bioanalista), entrega.
- [ ] Un resultado validado no se puede cambiar; anular solo con nota de crédito.
- [ ] Registrar una factura de compra con retención de ISLR.

CrossFit (en su instalación)
- [ ] Plan, socio nuevo (queda vencido), cobro (corre el vencimiento), entrada con cédula, pizarra publicada.
- [ ] Dar acceso a la app a un socio y entrar como él: solo ve lo suyo (ni clientes ni proveedores).

Los tres
- [ ] Panel del grupo del dueño con las ventas reales de los negocios instalados.
- [ ] Recargar la página: todo sigue ahí.

## Pruebas automáticas

```bash
PGHOST=/tmp/pg PGPORT=5433 PGUSER=postgres supabase/tests/correr.sh
```

```bash
tests/navegador/correr.sh
```
