# Base de datos de récipes y libro de controlados

**Respuesta corta: sí.** Y conviene, porque hoy la farmacia lleva esto en papel y a mano. Con una base de datos:

- el récipe queda guardado con su **foto**;
- el sistema **no deja despachar más de lo recetado** ni usar dos veces el mismo récipe especial;
- el **libro de controlados se llena solo** y cuadra con el inventario;
- la ficha del paciente avisa de **alergias** y de cuándo se le acaba un tratamiento.

La migración para Supabase está en `recipes_supabase.sql`, en esta misma carpeta. **Ya la probé** en un Postgres 16 con 20 casos: permisos por rol, despacho parcial, récipe repetido, libro que no se edita, otra farmacia que no ve nada… Todos dan el resultado esperado.

---

## 1. Qué exige la ley (lo que la base tiene que guardar)

### Récipe médico (medicamentos de venta con prescripción)

Resolución del Ministerio de Salud publicada en la **G.O. 40.131 del 19-03-2013**, vigente desde el 18-04-2013, según la reseña de *El Nacional* que reproduce *Salud y Fármacos*:

- Se receta por **principio activo**, con concentración, forma farmacéutica, vía de administración y dosis (art. 3).
- El récipe debe traer **10 datos obligatorios**, entre ellos el **registro del médico** y la **cédula del paciente** (art. 6). Si falta alguno, **no se despacha**.
- Va en **original y copia**: la farmacia se queda con el **original** y el paciente se lleva la **copia sellada** con la fecha del despacho, el nombre de la farmacia y su RIF.

*No encontré el texto oficial completo de la resolución. **Confirmar con la regente** cuáles son los 10 datos y cómo maneja hoy los tratamientos crónicos: en la práctica, a muchos pacientes se les devuelve el récipe sellado para que vuelvan por el resto.*

### Récipe especial (psicotrópicos y estupefacientes)

**Ley Orgánica de Drogas (G.O. 39.546, 2010)**:

| Artículo | Qué dice | Qué hace Cuadre |
| --- | --- | --- |
| 62 | Solo las farmacias venden estos medicamentos al público, y solo con el **récipe del talonario oficial**. Los de la lista IV pueden ir con récipe de uso particular. | El producto se marca como **controlado** y no sale sin récipe especial |
| 63 | Formulario **numerado**, con los datos del médico, el medicamento, la cantidad **en números y letras sin enmiendas**, la **identificación del paciente y de quien compra**, firma, fecha y **sello húmedo** del médico | Campos obligatorios y foto del récipe; el número no se puede repetir |
| 64 | **Prohibido venderlos a menores de edad** | La regente confirma la edad de quien compra |
| 65 | No se despacha **más de la posología oficial** | Se anota la posología y no se despacha más de lo recetado |
| 68 | La custodia y el control contable son responsabilidad del **farmacéutico regente** | Solo el usuario regente registra y despacha |
| 69 | **Libro especial sellado y foliado** por la autoridad; se registra **a diario** todo el movimiento, **sin tachaduras**; **resumen mensual al Ministerio** en los **primeros 10 días** del mes siguiente, con los duplicados de los récipes; los registros y récipes se guardan **al menos 2 años** | El libro digital solo agrega renglones, saca la existencia y prepara el resumen del mes |
| 70 | Si cambia el regente, se hace **inventario en el libro** y se manda copia firmada por los dos al Ministerio en **5 días** | Reporte de cambio de regente con la existencia del día |

**El libro oficial sigue siendo el de papel sellado por el Ministerio.** Cuadre no lo reemplaza: lleva el mismo registro, lo cuadra con el inventario y deja listo lo que se copia en el libro y el resumen mensual.

*Fuente: una transcripción no oficial de la ley. La ley vieja de 1993 decía que el récipe especial vence a los **5 días**; no confirmé si la de 2010 mantiene ese plazo. **Revisar con la regente o el Servicio Autónomo de Contraloría Sanitaria (SACS)** antes de activar un bloqueo por fecha.*

### Antibióticos

No encontré una norma vigente que trate los antibióticos aparte. Caen en la regla general del récipe médico. En Cuadre tienen su propio tipo para poder **contarlos y reportarlos**, y para que la caja **pida siempre el récipe**.

---

## 2. Cómo está armada la base

```
medicos ─┐
         ├─< recipes ─< recipe_items ─< dispensaciones ──> ventas (factura)
pacientes┘     │                              │
   │           └── foto (Storage privado)     └──> libro_controlados (si es controlado)
   ├─< paciente_alertas   (alergias, interacciones)
   └─< tratamientos       (crónicos → recordatorio por WhatsApp)
```

| Tabla | Para qué |
| --- | --- |
| `medicos` | Nombre, **MPPS**, colegio, especialidad. Se escribe una vez y luego se busca por MPPS. |
| `pacientes` | Cédula, nombre, teléfono, dirección (la pide el récipe especial) y **consentimiento** para recordatorios. Se enlaza con el cliente de Azul Puntos. |
| `paciente_alertas` | Alergias e interacciones, con los **principios activos** que las disparan (penicilina → amoxicilina, ampicilina…). |
| `tratamientos` | Crónicos: cuántas unidades al día y cuándo compró. De ahí sale **cuándo se le acaba**. |
| `recipes` | Tipo (médico, antibiótico o especial), número del récipe especial, médico, paciente, **quien compra**, fecha, foto, si el original se **archivó** o se **devolvió sellado**, y estado. |
| `recipe_items` | Cada medicamento recetado, con su posología y la **cantidad recetada**. |
| `dispensaciones` | Cada vez que se entrega algo de ese récipe: cantidad, lote, factura y quién despachó. Varias por récipe = **despacho parcial**. |
| `libro_controlados` | El libro especial: existencia inicial, compras, despachos, vencidos y ajustes, con la **existencia corrida** renglón por renglón. |
| `accesos_salud` | Quién abrió la ficha de cada paciente y cuándo. |

### Reglas que pone la base de datos, no la pantalla

- **No despachar de más:** si el récipe dice 2 cajas y ya salió 1, no deja sacar 2 más. El estado pasa solo de *abierto* a *parcial* y a *completo*.
- **Un récipe especial, una sola vez:** el número no se repite para el mismo médico.
- **Dos cajas a la vez:** el despacho bloquea el renglón mientras se guarda, para que no salga la misma unidad dos veces.
- **El libro solo crece:** nadie puede editar ni borrar un renglón, ni siquiera el administrador. Los errores se corrigen con un renglón de **ajuste** que exige una nota. Es lo mismo que pide la ley: sin tachaduras.
- **Despacho de controlado → libro:** al despachar un controlado, el renglón de salida se escribe solo.

---

## 3. Quién ve qué (seguridad por rol)

| | Regente | Dueño | Cajero | Almacén |
| --- | --- | --- | --- | --- |
| Ver pacientes, récipes y libro | Sí | Sí | **No** | No |
| Registrar récipes, despachar, escribir en el libro | **Sí** | No | No | No |
| Ver quién abrió cada ficha | No | **Sí** | No | No |
| Preguntar si un cliente tiene una alerta con un producto | Sí | Sí | **Sí (solo sí o no)** | No |

- **El cajero no ve datos de salud.** En la caja solo aparece *"requiere récipe"* o *"consulta a la regente antes de vender este producto a este cliente"*. Nunca ve el porqué.
- **El dueño ve, pero no autoriza.** La ley pone la responsabilidad en la regente. Si el dueño también es farmacéutico, se le asigna además el rol de regente.
- Las **fotos de los récipes** están en un almacenamiento privado, separado por farmacia. Solo los ven la regente y el dueño.
- **Otra farmacia que use Cuadre no ve nada de Azullab.** Cada consulta se filtra por farmacia en la base misma.

### Privacidad

Venezuela no tiene una ley general de datos personales, pero la Constitución protege la vida privada (art. 60) y da derecho a saber qué datos se guardan y a pedir que se corrijan (art. 28, *habeas data*). En la práctica:

- **Recordatorios por WhatsApp solo con permiso** del paciente. Es un campo de la ficha, apagado por defecto.
- Los mensajes **no nombran la enfermedad**: "su tratamiento de siempre", no "su pastilla de la tensión", salvo que el paciente lo acepte.
- **No se borra** antes de los 2 años que pide la Ley de Drogas. Después, la farmacia decide.
- **Registro de accesos:** el dueño ve quién abrió cada ficha.

---

## 4. Cómo se usa en el mostrador

1. **El cliente trae el récipe.** La regente escribe la **cédula**: si ya es paciente, aparecen sus datos; si no, se crea en el momento.
2. **El médico** se busca por **MPPS**. Si es nuevo, se agrega una vez.
3. **Foto del récipe** con la cámara de la caja o con el teléfono.
4. Se marca qué se receta y **cuánto se entrega hoy**. Si se lleva una parte, el resto queda **pendiente en su ficha**.
5. La venta pasa a la **caja** con el récipe enlazado. La factura sale normal.
6. **Etiqueta de despacho:** la impresora térmica saca una etiqueta con la fecha, "Azullab Farmacia" y el RIF, para pegarla en la copia del paciente como sello.
7. **Si es controlado:** la regente pone el número del récipe especial. El libro se escribe solo y la existencia baja.
8. **Fin de mes:** Cuadre arma el **resumen para el Ministerio** y las páginas del libro para pasarlas al libro sellado.

**Sin internet:** los récipes se guardan en la caja (SQLite) como las ventas, y la foto sube cuando vuelve la conexión. Las reglas de "no despachar de más" y "no repetir el récipe especial" también corren en la caja.

---

## 5. Lo que sale de tener la base

- **Historial del paciente:** qué compra, quién lo trata y qué le queda pendiente.
- **Recordatorios de crónicos** atados a Azul Puntos: "su tratamiento se está terminando, ¿se lo apartamos?". Es lo que hace volver al cliente.
- **Alertas de alergia** en la caja.
- **Reportes:** antibióticos despachados por mes, controlados por médico, récipes pendientes de retirar.
- **Inspección del SACS o del Ministerio:** el libro, los récipes y sus fotos, a la mano.

---

## 6. En qué fase va

En la propuesta, **Récipes y controlados** está en la **Fase 2**. Pero **si Azullab va a vender controlados desde que abra**, el **libro de controlados** tiene que estar desde el primer día. Mi recomendación:

- **Fase 1:** "requiere récipe" en la caja, el registro básico del récipe con su foto y el libro de controlados.
- **Fase 2:** la ficha completa del paciente, las alertas, los recordatorios por WhatsApp y los reportes.

---

## 7. Preguntas para la regente

1. ¿Van a vender **psicotrópicos o estupefacientes** desde el inicio? ¿Ya tienen el **libro sellado** y la **autorización del Ministerio**?
2. ¿Qué hace hoy con el **original** del récipe en los tratamientos crónicos: lo archiva o lo devuelve sellado?
3. ¿El récipe especial **vence a los 5 días**?
4. ¿Cómo manda hoy el **resumen mensual** al Ministerio: en papel o en línea?
5. ¿Qué **10 datos** revisa en el récipe médico antes de despachar?

---

## 8. Archivos

- `recipes_supabase.sql`: tablas, reglas, vistas (`libro_controlados_saldo`, `resumen_mensual_controlados`, `proximos_recordatorios`), funciones (`alerta_venta`, `ver_ficha`) y seguridad por rol, incluida la carpeta privada de fotos.
- La maqueta: **Récipes y controlados** ahora tiene tres pestañas (récipes, ficha del paciente y libro de controlados) y el formulario **Registrar récipe**.

## Fuentes

- [Ley Orgánica de Drogas (2010), transcripción en Pandectas Digital](https://pandectasdigital.blogspot.com/2017/02/ley-organica-de-drogas.html)
- [Ley Orgánica de Drogas, G.O. 39.546 (Tu Gaceta Oficial)](https://tugacetaoficial.com/leyes/ley-organica-de-drogas-gaceta-39546-2010-texto/)
- [Ley Orgánica sobre Sustancias Estupefacientes y Psicotrópicas (1993, derogada), en Justia](https://docs.venezuela.justia.com/federales/leyes-organicas/ley-organica-sobre-sustancias-estupefacientes-y-psicotropicas.pdf)
- [Salud y Fármacos: casi todas las medicinas requerirán prescripción (resolución de la G.O. 40.131, 2013)](https://www.saludyfarmacos.org/boletin-farmacos/boletines/may2013/p41351)
