# Cuadre · Grupo Azullab · Resumen del proyecto

Actualizado el 5 de noviembre de 2026.

**Estado:** los tres sistemas (Farmacia, Laboratorio y CrossFit) trabajan con datos reales en Supabase (proyecto `azullab`, región us-east-2). El código está en `main` del repositorio `josedanielgt1/azullab`. Pruebas: **279 de base de datos y 234 de navegador**, todas pasan.

---

## 1. Lo hecho en los últimos días

### Entrada y sesión
- Se entra con correo y clave, sin escoger rol: el sistema reconoce el rol.
- La sesión no se cierra al recargar. Se cierra sola tras 30 minutos sin uso.
- **Cerrar sesión ahora la cierra solo en ese equipo.** Antes, salir en el celular también sacaba a la persona de la caja.
- Se quitaron del menú «Alcance de la propuesta» y la fase 2. La fase 2 queda guardada y se activa con `FASE2 = true` en `js/cuadre-comun.js`.

### App instalable y entrada con PIN (nuevo)
- **App instalable:** el sistema se instala en la computadora como una aplicación, con su ícono y su propia ventana, y abre sin internet.
- **Equipos registrados:** el dueño o el gerente registra las computadoras de uso fijo (la caja, la recepción) en el menú «Este equipo».
- **Mientras el equipo no está registrado**, la sesión guardada abre sola, como siempre. Ya registrado, al cerrar la app y abrirla de nuevo pide el PIN.
- **PIN:** en un equipo registrado, cada persona entra con un PIN de 4 a 6 números, con o sin internet. La guía completa está en la sección 3.

### Tasa BCV automática (nuevo, ya activa en la base real)
- **Búsqueda automática:** la base busca sola la tasa en dolarapi.com cada 5 minutos, de 9:00 a 10:55 a. m. y de 5:00 a 6:55 p. m., y cada hora entre medio, de lunes a viernes. No hace falta que nadie entre al sistema.
- **Fecha valor:** cada tasa se guarda con el día en que vale. La que sale a las 5:20 p. m. es la de mañana y la del viernes en la tarde es la del lunes. Mientras tanto se sigue facturando con la de hoy, y a medianoche las cajas pasan solas a la nueva.
- **Cajas abiertas:** revisan cada 5 minutos si cambió la tasa del día. Si cambió, la toman y avisan: «Tasa BCV actualizada».
- **Tasa a mano:** si el dueño escribe la tasa en «Tasa BCV», esa manda sobre la automática.
- **Datos malos:** no se toma un salto de más de 25 % contra la tasa anterior.
- **Hora de Caracas:** la base usa la hora de Caracas. Antes, desde las 8 p. m., la base ya creía que era el día siguiente.
- **Feriados bancarios:** no se calculan solos. Si el BCV publica para el día después de un feriado, el sistema puede tomarla un día antes. En ese caso el dueño corrige la tasa a mano.

### Respaldo de lo hecho sin internet (nuevo)
- **Qué hay en la computadora:** casi nada. Todo el negocio (ventas, facturas, inventario, clientes, pacientes y socios) está en Supabase. Lo único que vive en la computadora son las ventas, órdenes y cobros hechos sin internet, hasta que suben.
- **Aviso:** mientras haya algo sin subir, una franja arriba dice «N ventas sin subir: no cierres ni borres los datos del navegador».
- **Carpeta de respaldo:** en «Este equipo» → «Escoger la carpeta de respaldo», por ejemplo `Documentos\Cuadre-respaldo`. Cada venta sin internet se copia ahí en `cuadre-farmacia-pendientes.json` (o `-laboratorio`, `-crossfit`), y el archivo se borra cuando todo subió. Funciona en Chrome y Edge.
- **Si borraron los datos del navegador:** entra, ve a «Este equipo» → «Recuperar desde un archivo de respaldo» y escoge ese archivo. Lo que falte en la base sube solo y no se repite nada. Un respaldo de otro negocio se rechaza.
- **Almacenamiento protegido:** el sistema le pide al navegador que no borre sus datos por su cuenta cuando falta espacio.
- **Limpieza:** el historial del reloj de la base se limpia solo cada domingo.

### Auditoría de seguridad (ya aplicada en la base real)
- Un cajero ya no puede facturar a cualquier precio ni falsificar el número de control de la imprenta.
- Sin internet, la venta no baja del 80 % del precio vigente.
- Los socios del CrossFit no pueden escribir datos del equipo.
- En el laboratorio solo se entrega un resultado validado por el bioanalista.
- Los nombres no aceptan código. La página filtra lo que llega de la base y bloquea mandar la sesión a sitios de terceros.
- La función `usuarios` (versión 2, subida) no deja cambiarle la clave a alguien que tiene más poder en otro negocio.
- La protección contra claves filtradas exige el plan Pro de Supabase. En el plan gratis se usan el mínimo de 8 caracteres y el requisito de mayúsculas, minúsculas y números.
- **Cómo se guardan el PIN y la sesión:** la sesión de cada persona queda cifrada en el equipo (AES-GCM) con una llave que sale de su PIN (PBKDF2, 310 000 vueltas). El PIN no se guarda.

### Cálculos
- **IGTF:** la base cobraba 3 % de IGTF en divisas y la caja no, así que la factura no cuadraba con lo cobrado. Ahora no se cobra, porque los tres negocios son contribuyentes ordinarios. Si alguno pasa a contribuyente especial, se pone `igtf = 3` en su fila de `empresas`.
- **App del socio:** el monto de renovación ahora lleva el IVA.
- **IVA:** el 16 % y el 8 %, los redondeos y las notas de crédito dan igual en la pantalla y en la base.

### Datos de muestra eliminados
- No quedan nombres, facturas, pacientes, socios, empleados, RIF ni datos de pago inventados. Tampoco aparecen si la base falla al entrar.
- Hay una prueba que recorre todas las pantallas con cada rol para confirmarlo.

### Velocidad
- Al entrar se hacían 25 consultas a la base, una tras otra. Ahora van a la vez: abrir pasa de 5,5 segundos a 1,4.

---

## 2. Pendiente

1. **GitHub Pages (hace falta para la app instalable, el PIN y «Olvidé mi clave»):**
   - En GitHub: Settings → Pages → rama `main`, carpeta raíz.
   - En Supabase → Authentication → URL Configuration:
     - Site URL: `https://josedanielgt1.github.io/azullab/`
     - Redirect URLs: `https://josedanielgt1.github.io/azullab/**`
2. **Claves:** en Supabase → Authentication → Sign In / Providers → Email, poner mínimo 8 caracteres y el requisito de minúsculas, mayúsculas y números.
3. **Talonario de contingencia:** en Configuración → Datos fiscales, el rango del talonario (desde y hasta). Sin él no se vende sin internet.
4. **Imprenta digital:** probablemente será The Factory HKA. Si también lleva la contabilidad, más adelante se podrían quitar los libros, la forma 30, las retenciones, el checklist del SENIAT y Ganancias y gastos. Por ahora no se ha quitado nada.
5. **Diferencial cambiario y conciliación bancaria:** necesitan los movimientos del banco.

---

## 3. Cómo se trabaja con la app instalada y el PIN

### La idea
- **Celular o computadora personal del dueño:** se entra con correo y clave, como siempre. No se registra.
- **Computadoras fijas del negocio (caja, recepción):** se registran una sola vez. Desde ahí cada persona entra con su PIN, aunque no haya internet.

### Requisitos
- **Sistema publicado con https:** GitHub Pages (pendiente 1). Abierto como archivo del equipo (`file://`) no hay PIN ni instalación, porque el navegador solo cifra en sitios seguros.
- **Navegador:** Chrome o Edge.
- **Primera vez de cada persona en cada equipo:** necesita internet. Hay que confirmar su clave al menos una vez.

### Paso a paso para probarlo en tu computadora
1. Abre `https://josedanielgt1.github.io/azullab/farmacia.html` en Chrome y entra con tu correo y tu clave.
2. En el menú, debajo de Usuarios, entra a **Este equipo**. Escribe un nombre (por ejemplo «Caja 1») y toca **Registrar este equipo**.
3. Toca **Crear mi PIN**. Son de 4 a 6 números, sin repetidos (1111) ni seguidos (1234).
4. Toca **Instalar la app en este equipo**. Si no aparece el botón, usa el ícono de instalar al final de la barra de direcciones (o menú ⋮ → «Instalar Azullab Farmacia»). Queda un ícono en el escritorio.
5. Cierra todo y abre la app desde el ícono. Sale **«¿Quién entra?»**: toca tu nombre, escribe el PIN y entras.
6. **Prueba sin internet:**
   1. Con internet, abre la app una vez para que guarde los archivos.
   2. Desconecta el wifi y abre la app.
   3. Entra con tu PIN.
   4. Haz una venta: sale con el talonario de contingencia (necesita el pendiente 3).
   5. Vuelve a conectar el wifi: la venta sube sola a la base.
7. **Prueba con otra persona:**
   1. En la pantalla del PIN, toca **Entrar con correo y clave** y entra con el usuario de un empleado.
   2. El sistema le pide **crear su PIN para este equipo**.
   3. Desde ahí, esa persona aparece en «¿Quién entra?».

### Reglas del PIN
| Situación | Qué pasa |
| --- | --- |
| PIN errado | Avisa cuántos intentos quedan |
| 5 PIN errados | Esa persona queda bloqueada en ese equipo; entra con su correo y su clave y se desbloquea |
| 7 días sin conectarse | El PIN vence; entra con correo y clave y vuelve a contar |
| 30 minutos sin uso | Se bloquea la pantalla y se vuelve a entrar con el PIN (también sin internet) |
| Cerrar sesión | Vuelve a «¿Quién entra?»; así se cambia de cajero en segundos |
| Recargar la página | No pide el PIN |
| Cerrar la app y abrirla de nuevo | Pide el PIN |
| El dueño le quita el acceso a alguien | Su PIN deja de servir apenas el equipo tenga internet |
| Se le olvidó el PIN | El dueño toca **Quitar PIN** en «Este equipo»; la persona entra con su clave y crea otro |
| Quitar el registro del equipo | Se borran todos los PIN guardados ahí |

### Cuidados importantes
- **Escoge la carpeta de respaldo en cada equipo de caja** («Este equipo»). Si Chrome pide permiso para la carpeta, acepta «Permitir siempre».
- **Cada sistema se registra e instala por separado:** farmacia, laboratorio y CrossFit.
- **Cada navegador es aparte:** registrar en Chrome no registra en Edge.
- **No borren los datos de navegación en las computadoras de la caja.** Se pierden el registro, los PIN y las ventas sin internet que todavía no hayan subido.
- **No registren equipos personales ni prestados.** El PIN es corto: su seguridad depende de que el equipo esté en el negocio. Si roban un equipo, el dueño le quita el acceso a esas personas en Usuarios y el PIN deja de servir en cuanto el equipo se conecte.
- **Sin internet**, los reportes y consultas muestran lo último que se guardó en el equipo. Todo se pone al día al volver la conexión.

---

## 4. Desinstalar y volver a instalar la app

### Desinstalar (Chrome o Edge en Windows)
1. Abre la app instalada (Azullab Farmacia).
2. En la ventana de la app, toca el menú **⋮** (arriba a la derecha) → **«Desinstalar Azullab Farmacia»**.
3. Marca **«Borrar también los datos»** si quieres empezar de cero. Esto borra el registro del equipo, los PIN y las ventas sin internet que no hayan subido; antes de marcarla, confirma que no queda nada pendiente.
4. Toca **Desinstalar**.

Otras formas: en Chrome, `chrome://apps` → clic derecho en la app → **Quitar de Chrome**; en Edge, `edge://apps` → **…** → **Desinstalar**; o en Windows: Configuración → Aplicaciones → buscar «Azullab» → **Desinstalar**.

### Volver a instalar (por ejemplo, en la reunión)
1. Abre `https://josedanielgt1.github.io/azullab/farmacia.html` en Chrome y entra con tu correo y tu clave.
2. Menú **Este equipo** → nombre del equipo → **Registrar este equipo**.
3. **Crear mi PIN**.
4. **Instalar la app en este equipo**, o el ícono de instalar en la barra de direcciones.
5. Cierra y abre la app desde el ícono: sale «¿Quién entra?».

