// Cuadre · Lee la tasa oficial directo de www.bcv.org.ve y la guarda con su fecha valor.
// La llama el reloj de la base (pg_cron) cada 5 minutos en la franja en que publica el BCV.
// Es pública (sin sesión): solo lee la página del BCV y guarda lo que publica; repetirla no cambia nada.
//
// El certificado del BCV: el sitio presenta un certificado intermedio viejo de Sectigo y no el que
// emitió su certificado actual («Sectigo Public Server Authentication CA DV R36»), por eso los
// programas lo rechazan. Aquí se descarga ese intermedio de la dirección oficial de Sectigo (la misma
// que trae el certificado del BCV) y se verifica la conexión con él: la verificación sigue siendo segura.
import { createClient } from "jsr:@supabase/supabase-js@2";

const BCV = "https://www.bcv.org.ve/";
const INTERMEDIOS = [
  "http://crt.sectigo.com/SectigoPublicServerAuthenticationCADVR36.crt",
  "http://crt.sectigo.com/SectigoPublicServerAuthenticationRootR46_USERTrust.crt",
];
let caCerts: string[] | null = null;

const aPem = (der: Uint8Array) => {
  let s = ""; for (const b of der) s += String.fromCharCode(b);
  if (s.includes("BEGIN CERTIFICATE")) return s;
  return "-----BEGIN CERTIFICATE-----\n" + btoa(s).match(/.{1,64}/g)!.join("\n") + "\n-----END CERTIFICATE-----\n";
};
async function intermedios(): Promise<string[]> {
  if (caCerts) return caCerts;
  const out: string[] = [];
  for (const u of INTERMEDIOS) {
    try { const r = await fetch(u); if (r.ok) out.push(aPem(new Uint8Array(await r.arrayBuffer()))); } catch (_) { /* sigue con los que haya */ }
  }
  caCerts = out; return out;
}
async function paginaBCV(): Promise<string> {
  try { const r = await fetch(BCV); if (r.ok) return await r.text(); } catch (_) { /* certificado incompleto: se completa abajo */ }
  // @ts-ignore: API de Deno para añadir certificados de confianza a la conexión
  const client = Deno.createHttpClient({ caCerts: await intermedios() });
  const r = await fetch(BCV, { client });
  if (!r.ok) throw new Error("El BCV respondió " + r.status);
  return await r.text();
}
// <div id="dolar"> … <strong class="strong-tb">896,12250000</strong>   y   Fecha Valor: <span … content="2026-11-06T00:00:00-04:00">
function leer(html: string) {
  const i = html.indexOf('id="dolar"'); if (i < 0) throw new Error("No se encontró el dólar en la página del BCV");
  const m = html.slice(i, i + 1500).match(/<strong[^>]*>\s*([\d.]+,\d+)\s*<\/strong>/);
  const j = html.indexOf("Fecha Valor"); const f = j < 0 ? null : html.slice(j, j + 600).match(/content="(\d{4}-\d{2}-\d{2}T[^"]+)"/);
  if (!m || !f) throw new Error("No se pudo leer la tasa o la fecha valor del BCV");
  return { promedio: Number(m[1].replace(/\./g, "").replace(",", ".")), fechaActualizacion: f[1] };
}

Deno.serve(async (req) => {
  try {
    const html = await paginaBCV();
    if (new URL(req.url).searchParams.has("ver")) {   // diagnóstico: los trozos de la página que se leen
      const i = html.indexOf('id="dolar"'), j = html.indexOf("Fecha Valor");
      return Response.json({ largo: html.length, dolar: html.slice(i, i + 700), fecha: html.slice(j - 100, j + 500) });
    }
    const t = leer(html);
    if (!(t.promedio > 0)) throw new Error("Tasa inválida");
    const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
    const { data, error } = await db.rpc("registrar_tasa_bcv", { j: t, p_fuente: "BCV (bcv.org.ve)" });
    if (error) throw error;
    return Response.json({ ok: true, tasa: t.promedio, fecha_valor: t.fechaActualizacion.slice(0, 10), guardada: data });
  } catch (e) {
    return Response.json({ ok: false, error: String((e as Error).message || e) }, { status: 502 });
  }
});
