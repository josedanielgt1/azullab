# Facturación sin máquina fiscal: imprenta digital

Revisado el 27-10-2026. Esto cambió **la semana pasada**; vuelve a revisar las fuentes antes de cada propuesta.

---

## 1. Qué pasó con las máquinas fiscales

| Fecha | Qué pasó |
| --- | --- |
| 22-07-2026 | Según dos distribuidores, el SENIAT ordenó a fabricantes y distribuidores **parar la venta de máquinas fiscales nuevas "hasta nuevo aviso"** mientras evalúa los modelos. No lo encontré en Gaceta; es información de la industria. |
| 12-08-2026 | **Providencia SNAT/2026/00084** (G.O. 43.435): deroga la SNAT/2024/000121. **Ya no hay que homologar el software de facturación.** |
| 21-10-2026 | **Providencia SNAT/2026/00093** (G.O. 43.484): nuevo régimen de facturación. **La máquina fiscal deja de ser obligatoria.** |
| **19-04-2027** | **Entra en vigencia la 00093** (180 días después de publicada). Hasta el 18-04-2027 siguen las normas anteriores. |

Lo que dice la 00093 cuando entre en vigencia:

- **El comerciante elige libremente cómo factura** (art. 5) entre:
  1. Medios digitales: el **portal web y la app gratuitos del SENIAT** (todavía no existen; no tienen fecha) o una **imprenta digital u otro proveedor tecnológico autorizado** (art. 4.1).
  2. **Máquina fiscal** (art. 4.2), para quien ya la tenga o la quiera.
- **Se prohíbe la forma libre.** Los talonarios en papel quedan **solo para contingencias**: apagones, caída del internet, fallas de equipo (art. 6). Hay que tenerlos siempre en el local.
- **Después de una contingencia**, las facturas en papel se envían **en PDF al día siguiente** a la imprenta digital o a la API del SENIAT (art. 7).
- **Número de control:** dos dígitos de serie y un correlativo de hasta ocho (art. 9). Ejemplo: `00-00001249`. Lo **asigna la imprenta digital** (art. 42).
- La factura lleva **fecha y hora exacta** de emisión.
- Las imprentas autorizadas antes **siguen autorizadas** (Transitoria Tercera).
- Quien cambie de medio de emisión lo **informa a su Gerencia Regional** del SENIAT (Transitoria Segunda).

## 2. Qué hace Azullab mientras tanto (de hoy al 18-04-2027)

**Aquí hay una zona gris y hay que decirlo claro.**

- Con la norma vieja (Providencia 0071, art. 8, literal k), quien **vende productos farmacéuticos** al consumidor final **debe** usar máquina fiscal.
- Pero hoy **no se venden máquinas nuevas**, y el Ejecutivo anunció el 21-10 que suspendía la obligación "a partir de este momento", aunque la Gaceta dice que rige en 180 días.

Lo prudente para una farmacia nueva:

1. Que **su contador** pida por escrito a la Gerencia Regional del SENIAT en Mérida autorización para facturar por **imprenta digital**, citando que no hay máquinas a la venta. Las imprentas piden esa carta como requisito para darte de alta.
2. Mientras llega la respuesta, que facture con un **talonario de una imprenta autorizada** y lo registre todo en Cuadre.
3. Cuando llegue la autorización, o el 19-04-2027, pasa a **imprenta digital** sin cambiar nada en el sistema.

*Confirmar este camino con el contador de Azullab y con el SENIAT de Mérida.* No es asesoría legal; es lo que dicen las normas y las noticias revisadas.

## 3. Recomendación para Cuadre

**Cuadre factura a través de imprentas digitales por su API**, con un conector que sirve para cualquier proveedor. La máquina fiscal queda como **módulo** para el cliente que ya tenga una, y el portal del SENIAT como conector futuro si publica una API.

Por qué:

- Funciona **hoy** (con autorización) y **después del 19-04-2027** sin cambios.
- Desde que se derogó la 121, **Cuadre no necesita homologarse**: la validez fiscal la da la imprenta autorizada que asigna el número de control.
- No hay que comprar un equipo que hoy no se consigue.
- El cliente recibe su factura **impresa o por WhatsApp**, con QR para verificarla.

## 4. Cuánto cuesta (lo que hay publicado)

| Proveedor | Precio publicado | API |
| --- | --- | --- |
| CG La Imprenta Digital | **100 facturas por $49** (≈ $0,49 c/u) · **500 por $199** (≈ $0,40 c/u) · plan empresarial desde 1.000 números, a cotizar · su tabla comparativa dice **$0,25 por factura** | Sí, REST con token y ambiente de pruebas |
| The Factory HKA (imprenta digital) | No publica precio | Sí, REST con token (`/api/Autenticacion`, `/api/Emision`, `/api/Anular`, `/api/DescargaArchivo`, según su conector para Odoo) |
| Serdimpre | Cotización por WhatsApp | No lo menciona |
| Smart Factura | No publica precio | No lo menciona; envía por correo, SMS y WhatsApp |
| Portal y app del SENIAT | Anunciados **gratis**; sin fecha ni API conocida | Desconocida |

**Ojo con esto, porque cambia la venta.** La imprenta cobra **por cada factura** y una farmacia hace muchas ventas pequeñas.

| Facturas al día | Al mes | A $0,25 | A $0,40 |
| --- | --- | --- | --- |
| 30 | 900 | $225 | $360 |
| 50 | 1.500 | $375 | $600 |

Eso puede costar más que el propio sistema. Por eso:

- **Ese costo lo paga la farmacia directo a la imprenta.** No va dentro del precio de Cuadre; en la propuesta se pone aparte.
- Hay que **cotizar 2 o 3 imprentas por volumen** (1.000 a 2.000 números al mes) y preguntar si los paquetes vencen.
- Hay que **preguntar por su programa de aliados o revendedores**: Cuadre podría comprar números por volumen y revenderlos, o cobrar comisión. Es un ingreso recurrente.
- Hay que **vigilar la app gratuita del SENIAT**: si sale con API, Cuadre la conecta y el costo por factura baja a cero.

Además hace falta una **impresora térmica común de 80 mm** (no fiscal) para imprimir la factura, o mandarla por WhatsApp. Precio a cotizar en Mérida.

### Comparación para una farmacia de ~500 facturas al mes

| | Máquina fiscal | Imprenta digital | Talonario |
| --- | --- | --- | --- |
| Costo inicial | ~$700 (precio de referencia) | $0 | Bajo (cotizar) |
| Costo mensual | Rollos y mantenimiento (cotizar) | ~$125 a $199 (de $0,25 a $0,40 por factura) | Talonarios nuevos |
| Primer año | ~$700 + mantenimiento | ~$1.500 a $2.400 | Bajo |
| Se paga sola en | 4 a 6 meses frente a la imprenta | Nunca: es gasto fijo | — |
| Sin internet | Factura igual | Necesita talonario de contingencia | No necesita internet |
| ¿Se puede hoy? | **Venta pausada desde julio**: hay que confirmar con el distribuidor | Sí, con autorización | Puente mientras tanto, en zona gris |
| Después del 19-04-2027 | Sigue válida (art. 4.2) | Válida | **Solo para contingencias** |

**Conclusión:**

1. **Máquina fiscal**, si se puede comprar legalmente. Es la más barata desde el quinto o sexto mes y no depende del internet.
2. **Talonario** solo como puente hasta conseguir la máquina o hasta abril de 2027, con Cuadre registrando cada factura para los libros.
3. **Imprenta digital** solo si no hay máquinas a la venta, o si la app gratuita del SENIAT sale con API.

## 5. Cómo se une con Cuadre

```
Caja Cuadre ──(1) datos de la factura──▶ Conector de facturación ──(2) REST + token──▶ Imprenta digital
     ▲                                                                                    │
     └──(4) imprime en térmica / envía PDF por WhatsApp ◀──(3) n.° de control, hora, QR, PDF─┘
```

1. El cajero cobra; Cuadre arma el documento con:
   - emisor y cliente (cédula o RIF, o consumidor final);
   - renglones con su alícuota (exento o 16 %);
   - totales en Bs con la referencia en dólares y la tasa BCV;
   - formas de pago.
2. El conector lo manda a la API de la imprenta con una **clave única por venta**, para que no se facture dos veces si se repite el envío.
3. La imprenta valida y devuelve el **número de control**, la fecha y hora, el **enlace o QR de verificación** y el **PDF**.
4. Cuadre imprime en la térmica o envía el PDF por WhatsApp o correo. Guarda la solicitud y la respuesta completas como respaldo.

El mismo conector maneja **notas de crédito**, **anulaciones** y la **consulta del estado** de cada documento.

Los **libros** los arma Cuadre con lo que devuelve la imprenta:

- facturas con RIF, una por una;
- consumidor final por día, del primer al último número de control;
- facturas de contingencia con el número del talonario.

*Confirmar el formato con el contador.*

**Diseño del conector:** una sola interfaz (emitir, anular, nota de crédito, estado, PDF) y un adaptador por proveedor: HKA, CG, Unidigital, la máquina fiscal (módulo) y, más adelante, el SENIAT. Cambiar de imprenta es cambiar una configuración, no reprogramar el sistema.

## 6. Sin internet: el talonario de contingencia

**La imprenta digital necesita internet para dar el número de control.** Esto es lo que más cambia frente a la máquina fiscal, y en La Azulita es importante.

- Sin internet, la caja sigue vendiendo y pide el **número del talonario de contingencia**. El cajero llena la factura en papel; Cuadre registra la venta, descuenta el inventario y guarda los datos.
- Al volver la conexión, Cuadre **genera el PDF de cada factura de contingencia y lo manda a la imprenta**, como pide el art. 7.
- **Recomendación fuerte:** un **segundo acceso a internet** (un router con chip de datos móviles o un enlace satelital) para que el talonario sea la excepción. Va en la propuesta junto con la UPS.
- *Preguntar a cada imprenta* si permite trabajar sin conexión con rangos de números asignados por adelantado. Su API tiene un servicio de "asignar numeraciones", pero no está claro que sirva para eso.

## 7. Contribuyente ordinario primero; contribuyente especial como módulo

- **Base de Cuadre: contribuyente ordinario.** IVA exento y 16 %, libros, inventario y **retenciones de ISLR** al pagar alquiler, honorarios y servicios (toda empresa las hace; ver `03 - Retenciones SENIAT.md`). Sin IGTF ni retenciones de IVA.
- **Módulo contribuyente especial** (se activa solo si aplica):
  - IGTF de 3 % en pagos con divisas (Providencia SNAT/2022/000013);
  - retenciones de IVA como agente, con sus comprobantes y las columnas en los libros.
- El padrón de especiales se está depurando: según la Providencia SNAT/2026/00099, que rige desde el 01-11-2026, el SENIAT pasaría de unos 132.000 a 44.000 especiales. Hay que **revisar en el portal del SENIAT si el cliente es especial** antes de configurar.

## 8. Qué preguntarle a cada imprenta al cotizar

1. Precio por número de control para 1.000, 1.500 y 2.000 al mes; si los paquetes vencen y si hay costo de alta.
2. Documentación de la API, ambiente de pruebas y tiempo de respuesta.
3. Número de su autorización del SENIAT.
4. Cómo es el PDF y el QR; si envía por WhatsApp o correo.
5. Si permite emitir sin conexión o con rangos asignados por adelantado.
6. Qué requisitos pide al cliente para darlo de alta (carta, RIF, acta, cédulas).
7. Si tienen **programa de aliados o revendedores** para desarrolladores como Cuadre.
8. Soporte: horario, canal y qué pasa si su servicio se cae.

## Fuentes

- [Providencia SNAT/2026/00093: medios de emisión, número de control, contingencia (resumen del articulado)](https://docs.cachicamo.app/fiscal/providencia00093-emision-facturas-2026)
- [Boletín de Grant Thornton sobre la PA 00093: vigencia el 19-04-2027 y derogatorias](https://www.grantthornton.com.ve/globalassets/1.-member-firms/venezuela/2026/boletin-informativo-pa-00093-facturacion.pdf)
- [Gerencia y Tributos: nueva norma de facturación 00093](https://gerenciaytributos.blogspot.com/2026/10/nueva-norma-de-facturacion-seniat-00093-2026.html)
- [El Diario: el SENIAT oficializa que las máquinas fiscales ya no son obligatorias](https://eldiario.com/2026/10/22/eliminacion-maquinas-fiscales-venezuela/)
- [2001online: el SENIAT aclara las nuevas reglas](https://2001online.com/nacionales/seniat-aclara-las-nuevas-reglas-tras-eliminar-la-obligatoriedad-de-maquinas-fiscales-en-venezuela-2026102213330)
- [Ciudad Barquisimeto: publicación en Gaceta 43.484](https://ciudadbqto.com/2026/10/24/publican-en-gaceta-oficial-suspension-del-uso-obligatorio-de-maquinas-fiscales/)
- [Nayma Consultores: suspensión de máquinas fiscales y depuración de contribuyentes especiales](https://naymaconsultores.com/suspension-de-maquinas-fiscales-y-cambios-en-los-contribuyentes-especiales/)
- [Negocios Gestionados: derogatoria de la 121 y pausa en la venta de máquinas fiscales](https://negociosgestionados.com/cambios-seniat-2026-providencia-121/)
- [SENIAT paraliza ventas de impresoras fiscales (Sistemas 4S, título del artículo)](https://sistemas4s.com/seniat-paraliza-ventas-impresoras-fiscales/)
- [Forvis Mazars: derogatoria de sistemas homologados](https://www.forvismazars.com/ve/es/insights/forvis-mazars-insights/fmi-0726-derogatoria-de-sistemas-homologados)
- [El Diario: qué cambia sin la homologación de sistemas](https://eldiario.com/2026/08/16/eliminacion-homologacion-facturacion/)
- [Providencia 0071, art. 8 (venta de productos farmacéuticos)](https://www.mileoconsultores.com/wp-content/uploads/2015/02/PA00071_2011.pdf)
- [Gerencia y Tributos: quién está obligado a usar máquina fiscal](https://gerenciaytributos.blogspot.com/2015/05/quien-esta-obligado-usar-maquina-fiscal.html)
- [CG La Imprenta Digital: planes y precios](https://calidad.cgimprenta.digital/pricing)
- [CG La Imprenta Digital: requisitos y API](https://cgimprenta.digital/)
- [Conector de Odoo para la imprenta digital de The Factory HKA](https://apps.odoo.com/apps/modules/19.0/l10n_ve_imprenta_digital_hka)
- [Conector genérico de imprentas digitales para Odoo](https://apps.odoo.com/apps/modules/19.0/l10n_ve_imprenta_digital)
- [Serdimpre](https://serdimpre.com/) · [Smart Factura](https://www.smartfactura.net/)
- [El Estímulo: lo que se sabe de la app de facturación del SENIAT](https://elestimulo.com/elinteres/empresas/2026-10-15/la-app-de-facturacion-que-promete-el-seniat-lo-que-se-sabe-y-lo-que-cambiaria-para-las-pymes/)
