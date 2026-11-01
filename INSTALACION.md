# Instalación y revisión · Grupo Azullab

Pasos para dejar los tres sistemas funcionando con la base real (Supabase, proyecto `azullab`) y una lista para revisarlos antes de entregar.

## 1. Base de datos (una sola vez)

1. Supabase → **SQL Editor** → New query.
2. Si nunca pegaste nada: pega `supabase/instalar_en_sql_editor.sql` completo y dale **Run** (debe decir «Instalación lista: 3 empresas»).
3. Luego pega `supabase/pendiente_sql_editor.sql` completo y dale **Run** (debe decir «Listo: migraciones aplicadas»).
4. Para comprobar: **Table Editor** debe mostrar, entre otras, `productos`, `ordenes`, `socios`, `recipes`, `libro_controlados`.

Cada vez que haya migraciones nuevas, se arma el archivo con:

```bash
supabase/armar_sql_editor.sh 0017 > supabase/pendiente_sql_editor.sql
```

## 2. Usuarios

1. **Authentication → Sign In / Providers**: «Allow new users to sign up» apagado.
2. El primer usuario que se creó es el dueño de los tres negocios.
3. **Función `usuarios`** (para «Nuevo usuario» y «Dar acceso a la app» del socio): Edge Functions → Deploy a new function → Via Editor → nombre `usuarios` → pegar `supabase/functions/usuarios/index.ts` → Deploy.
4. Sin la función: crea el usuario en Authentication → Users → Add user, y en el sistema usa «Dar acceso» con su correo.

## 3. Publicar (para usarlo desde cualquier equipo y sin internet)

1. GitHub → Settings → Pages → Deploy from a branch → `claude/inspiring-pascal-ljb7rr` (o `main` cuando se una) → / (root).
2. Supabase → Authentication → URL Configuration: Site URL `https://josedanielgt1.github.io/azullab/` y Redirect URLs `https://josedanielgt1.github.io/azullab/**` (para «Olvidé mi clave»).
3. Publicado en https, cada equipo guarda el sistema y abre aunque no haya internet.

## 4. Primer día en cada negocio (lo hace el dueño)

1. **Configuración → Datos fiscales**: razón social, RIF, domicilio, imprenta, talonario de contingencia (primer y último número), excedente del mes anterior. Marcar «confirmados» (sin eso no se factura).
2. **Tasa BCV**: se carga sola al entrar el dueño; si falla, «Tasa BCV» a mano.
3. **Usuarios**: crear al equipo con su rol (cajero, regente, almacén, atención, bioanalista, toma de muestras, coach).
4. **Catálogo**:
   - Farmacia: Proveedores (droguerías con RIF) y productos; la existencia entra al recibir la primera compra.
   - Laboratorio: «Cargar el catálogo base» y ajustar precios, referencias y reactivo de cada examen.
   - CrossFit: Membresías y pagos → planes, productos y horario de clases.

## 5. Lista de revisión antes de entregar

Farmacia
- [ ] Crear un producto, recibir una compra con número y control de factura, verlo en el Libro de Compras.
- [ ] Vender con factura; la existencia baja del lote que vence primero; aparece en Mi turno y en el Libro de Ventas.
- [ ] Devolución con nota de crédito: la mercancía vuelve al lote.
- [ ] Un controlado no se vende sin récipe especial del paciente; la venta queda en el libro de controlados.
- [ ] Sin internet (desconectar el wifi): vender con talonario; al volver, sube solo.
- [ ] Cajero: no ve ganancias, compras, récipes ni usuarios.

Laboratorio
- [ ] Paciente nuevo, orden con factura, toma, resultados, validación (solo el bioanalista), entrega.
- [ ] Un resultado validado no se puede cambiar; anular solo con nota de crédito.
- [ ] Registrar una factura de compra con retención de ISLR.

CrossFit
- [ ] Plan, socio nuevo (queda vencido), cobro (corre el vencimiento), entrada con cédula, pizarra publicada.
- [ ] Dar acceso a la app a un socio y entrar como él: solo ve lo suyo.

Los tres
- [ ] Panel del grupo del dueño con las ventas reales de los tres negocios.
- [ ] Recargar la página: todo sigue ahí.

## Pruebas automáticas

```bash
PGHOST=/tmp/pg PGPORT=5433 PGUSER=postgres supabase/tests/correr.sh
```

```bash
tests/navegador/correr.sh
```
