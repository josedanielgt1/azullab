// Cuadre · Carga la tasa oficial del BCV en la tabla tasas_bcv.
// Se programa cada hora en Supabase (Integrations → Cron) o se llama a mano:
//   supabase functions deploy tasa-bcv
//   curl -X POST https://<proyecto>.supabase.co/functions/v1/tasa-bcv -H "Authorization: Bearer <service_role>"
// Misma fuente que usa hoy laboratorio.html.
import { createClient } from "jsr:@supabase/supabase-js@2";

const FUENTE = "https://ve.dolarapi.com/v1/dolares/oficial";

Deno.serve(async () => {
  const r = await fetch(FUENTE, { headers: { accept: "application/json" } });
  if (!r.ok) return Response.json({ ok: false, error: `La fuente respondió ${r.status}` }, { status: 502 });
  const j = await r.json();
  const tasa = Number(j.promedio ?? j.venta);
  if (!(tasa > 0)) return Response.json({ ok: false, error: "La fuente no trajo una tasa válida", j }, { status: 502 });

  // Fecha de la publicación, en hora de Venezuela
  const en = j.fechaActualizacion ? new Date(j.fechaActualizacion) : new Date();
  const fecha = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Caracas" }).format(en);

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { error } = await db.from("tasas_bcv").upsert({ fecha, tasa, fuente: "BCV vía dolarapi.com" }, { onConflict: "fecha" });
  if (error) return Response.json({ ok: false, error: error.message }, { status: 500 });
  return Response.json({ ok: true, fecha, tasa });
});
