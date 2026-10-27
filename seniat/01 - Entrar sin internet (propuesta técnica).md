# Entrar al sistema sin internet

**El problema:** la maqueta muestra que la caja sigue vendiendo si el internet se cae **con la sesión ya abierta**. Pero si un día la farmacia amanece sin internet, una página web normal **ni siquiera abre**: el navegador tiene que descargarla, el login tiene que hablar con el servidor (Supabase) y la sesión vence en horas. Esto se resuelve desde la arquitectura, no con un parche.

---

## Por qué falla una web normal

1. **La página no carga:** sin internet, el navegador no tiene de dónde bajar la aplicación.
2. **El login no responde:** usuario y contraseña se verifican en la nube.
3. **La sesión vence:** el token de acceso dura poco y para renovarlo hace falta internet.
4. **No hay datos:** productos, precios, tasa y clientes viven en la nube.
5. **La factura:** la imprenta digital necesita internet para dar el número de control (ver punto 4).

---

## La solución: la caja trabaja en local y la nube se sincroniza

### 1. El sistema se instala en la caja

En vez de abrir una dirección web, la caja tiene **"Cuadre Caja" instalada** con su ícono en el escritorio. Hay dos maneras:

| | App instalable del navegador (PWA) | App de escritorio (Tauri) — **recomendada** |
| --- | --- | --- |
| Abre sin internet | Sí, si el navegador guardó la app (*service worker*) | Sí, siempre |
| Base de datos local | Del navegador (IndexedDB o SQLite web); el navegador puede borrarla si falta espacio | SQLite en el disco, estable |
| Impresora fiscal | Solo Chrome o Edge en computadora, por **Web Serial**, programando el protocolo de la impresora | Acceso directo al puerto y a la librería del fabricante |
| Actualizaciones | Automáticas | Automáticas (el instalador se actualiza solo) |
| Costo de hacerla | Bajo | Medio: es la misma interfaz web metida en una app |

**Recomendación: app de escritorio con Tauri** para las cajas, con la **misma interfaz** que ya tenemos (Next.js y Papel Fiscal), y **web normal** para el dueño desde el teléfono. La app de escritorio también maneja sin problemas la impresora térmica y, si un cliente la tiene, la máquina fiscal.

### 2. Los datos viven en la caja y se sincronizan

- Cada caja tiene su **base local (SQLite)** con productos, lotes, precios, tasa del día, clientes y los usuarios de esa sede.
- Todo lo que se hace sin internet queda en una **cola de envío** y se sube en orden cuando vuelve la conexión.
- **El inventario es una suma de movimientos, no un número que se edita.** Cada venta, compra, vencido o ajuste es un renglón nuevo, igual que el registro del art. 177. Dos cajas vendiendo sin internet nunca se pisan: al sincronizar solo se suman renglones. Los precios y las fichas de producto solo los cambian el dueño o el regente, y gana el último cambio.
- Herramienta para sincronizar: **PowerSync** conecta Supabase con SQLite local. Su plan gratis se desactiva tras una semana sin uso; el plan Pro cuesta desde $49 al mes. Como nuestras ventas solo se agregan y nunca se editan, también podemos hacer **nuestra propia sincronización** (una tabla de envíos pendientes y una descarga por fecha de cambio) sin pagar mensualidad. Recomiendo empezar con la propia y dejar PowerSync como plan B.

### 3. Entrar con PIN sin internet ("llave del equipo")

1. **Registrar la caja una sola vez, con internet:** el dueño entra, le pone nombre ("Caja 1") y la autoriza. La caja descarga sus datos y los usuarios de la sede.
2. **Cada usuario crea un PIN** de 4 a 6 dígitos. En la caja se guarda solo una **huella cifrada del PIN** (no el PIN) y su rol.
3. **Entrar sin internet:** el sistema detecta que no hay red y muestra **"Sin internet: entra con tu PIN"**. Valida el PIN en la caja y abre la sesión con los mismos permisos de siempre.
4. **Al volver el internet:** la caja se reporta con la nube. Si el dueño desactivó a un usuario, esa sesión se cierra en ese momento.
5. **Límites de seguridad:**
   - Una caja puede trabajar sin hablar con la nube hasta **72 horas**. Pasado ese plazo pide conexión para seguir, y el plazo se puede ajustar.
   - Tres PIN fallidos bloquean al usuario en esa caja.
   - El dueño puede desautorizar una caja robada desde su teléfono.

Además:

- **Tasa BCV sin internet:** se usa la última tasa guardada, con un aviso visible ("Tasa del 26-10, sin actualizar"). El dueño o el regente pueden escribirla a mano.
- **Panel del dueño desde el teléfono:** ese sí necesita internet, porque es la vista de la nube. Ve lo que las cajas ya subieron.

### 4. La factura sin internet (actualizado el 27-10-2026)

Cuadre va a facturar por **imprenta digital**, y la imprenta **necesita internet** para dar el número de control. Sin internet:

- La caja sigue vendiendo y pide el número del **talonario de contingencia** autorizado, que se guarda en la farmacia (Providencia SNAT/2026/00093, art. 6). El cajero llena la factura en papel y Cuadre la registra.
- Al volver la conexión, Cuadre manda **en PDF** esas facturas a la imprenta, al día siguiente como máximo (art. 7).
- Por eso conviene un **segundo acceso a internet** (un router con chip de datos o un enlace satelital) además de la UPS.
- Si el cliente ya tiene **máquina fiscal** (módulo), esa sí factura sin internet porque va conectada por cable a la caja. Para conectarla hay que pedir al distribuidor el kit de desarrollo (SDK) de su modelo.

El detalle está en `02 - Facturación sin máquina fiscal (imprenta digital).md`.

### 5. Dos cajas sin internet

- **Fase 1:** cada caja trabaja sola. Al volver el internet, los movimientos se suman. El riesgo es que las dos cajas vendan la última unidad del mismo producto. El sistema lo marca como **existencia negativa** y avisa para revisarlo. En una farmacia del tamaño de Azullab pasa muy poco.
- **Fase 2 (opcional):** la Caja 1 también hace de **servidor local** por la red de la farmacia (el router funciona sin internet si tiene luz), así las dos cajas ven el mismo inventario al instante.

### 6. Sin luz

- **UPS** para cada caja, la impresora térmica y el router. Recomiéndala en la propuesta: es lo que más corta ventas en La Azulita.
- La base local se guarda en cada operación. Si la computadora se apaga de golpe, no se pierde la venta ya cobrada.
- **Plan de contingencia:** una laptop con Cuadre Caja instalada y registrada como "Caja de respaldo".

---

## Cómo se ve en la maqueta

La pantalla de entrada ahora tiene el caso **"amaneció sin internet"**: se activa con el botón "Sin conexión" de la pantalla de entrada. Muestra la caja autorizada, la fecha de los datos guardados en el equipo y la entrada con PIN. Tómalo como el guion para explicárselo al cliente el 28.

---

## Orden de trabajo para construirlo de verdad

1. Modelo de datos con **inventario por movimientos** y tablas con fecha de cambio. Va primero, porque cambiarlo después cuesta caro.
2. Caja en **Tauri** con SQLite local y la misma interfaz.
3. **Registro del equipo**, PIN y sesión sin conexión.
4. **Sincronización**: cola de envío y descarga por cambios.
5. **Conector de facturación**: imprenta digital por API, talonario de contingencia y, como módulo, la máquina fiscal.
6. Pruebas de corte: desconectar el internet a mitad de una venta, apagar de golpe, dos cajas vendiendo el mismo producto.

## Fuentes

- [PowerSync con Supabase: base local y cola de envío](https://docs.powersync.com/integrations/supabase)
- [Precios de PowerSync](https://www.powersync.com/pricing)
- [Límites reales de una PWA sin conexión (Edana, 2026)](https://edana.ch/en/2026/04/05/can-a-web-app-pwa-really-work-offline-like-a-native-app/)
- [Web Serial API: compatibilidad por navegador](https://caniuse.com/web-serial)
- [Web Serial API (MDN)](https://developer.mozilla.org/docs/Web/API/Web_Serial_API)
