# Grupo Azullab · sistemas Cuadre

Sistemas de la **farmacia**, el **laboratorio clínico** y el **CrossFit** del Grupo Empresarial Azullab (La Azulita, Mérida), con el diseño **Papel Fiscal** de Cuadre. Guardan en **Supabase** (proyecto `azullab`): se entra con correo y clave (o PIN en un equipo registrado), cada quien ve lo de su rol y la base hace cumplir las reglas fiscales y de inventario.

**Un RIF por negocio.** Los tres son contribuyentes distintos: cada uno factura con su propio correlativo, sus libros de compras y ventas y sus datos fiscales. El medio de facturación se escoge por negocio (`empresas.medio_factura`): la farmacia factura por **máquina fiscal**; el laboratorio y el CrossFit quedan con imprenta digital.

| Qué | Dónde |
| --- | --- |
| Pantallas | `index.html` (portada), `farmacia.html`, `laboratorio.html`, `crossfit.html` (`crossfit.html#socio` es la app del socio) |
| Lógica con la base | `js/` (`cuadre-comun.js`, `cuadre-equipo.js`, `farmacia-real.js`, `maquina-fiscal.js`, `laboratorio-real.js`, `crossfit-real.js`, `config.js`) |
| Sin internet | `sw.js` y los `manifest-*.webmanifest`: la app se instala y abre sin conexión |
| Base de datos | `supabase/migrations` (una migración numerada por cambio), `supabase/tests`, `supabase/functions` (`usuarios`, `tasa-bcv`) |
| Pruebas de pantallas | `tests/navegador` (Chromium con un Supabase simulado) |
| Máquina fiscal | `docs/agente-maquina-fiscal.md` (protocolo del agente de la caja) |
| Diseño | `papel-fiscal/` |
| Maqueta vieja de la farmacia, para mostrarla | `maqueta/` |

Qué es real y qué falta: `PLAN.md`. Instalar y revisar: `INSTALACION.md`.

## Cómo se trabaja

- Todo cambio va en una rama desde `main`, con su PR. Commits en español.
- Cada cambio de base es una migración nueva, con sus pruebas. En producción se aplica pegando `supabase/pendiente_sql_editor.sql` en el SQL Editor.
- Antes de dar algo por listo:

```bash
PGHOST=/tmp/pg PGPORT=5433 PGUSER=postgres supabase/tests/correr.sh
tests/navegador/correr.sh
```
