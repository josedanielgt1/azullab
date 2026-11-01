// Cuadre · Crea usuarios y les cambia la clave, desde la pantalla Usuarios.
// Necesita la clave secreta, que Supabase le da sola (SUPABASE_SERVICE_ROLE_KEY):
// por eso esto no puede ir en el navegador.
//
// Subirla: Supabase → Edge Functions → Deploy a new function → Via Editor,
// nombre "usuarios", pegar este archivo y Deploy.
//
// POST {accion:"crear", empresa_id, correo, clave, nombre, rol, caja?}
// POST {accion:"clave", empresa_id, user_id, clave}
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const responder = (cuerpo: unknown, status = 200) =>
  new Response(JSON.stringify(cuerpo), { status, headers: { ...CORS, "Content-Type": "application/json" } });
const ROLES = ["dueno", "gerente", "regente", "cajero", "almacen", "atencion", "bioanalista", "coach", "toma_muestras"];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return responder({ error: "Usa POST" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const auth = req.headers.get("Authorization") ?? "";
  // Cliente con el token de quien llama: la base decide si puede
  const comoUsuario = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } } });
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

  let b: Record<string, string>;
  try { b = await req.json(); } catch { return responder({ error: "Datos inválidos" }, 400); }
  const rol = b.accion === "crear" ? b.rol : "cajero";
  if (!ROLES.includes(rol)) return responder({ error: "Rol inválido" }, 400);

  const { data: puede, error: e1 } = await comoUsuario.rpc("puedo_crear_usuarios", { p_empresa: b.empresa_id, p_rol: rol });
  if (e1 || !puede) return responder({ error: "Solo el dueño o el gerente manejan usuarios" }, 403);
  if (!b.clave || b.clave.length < 8) return responder({ error: "La clave debe tener al menos 8 caracteres" }, 400);

  if (b.accion === "crear") {
    const correo = (b.correo ?? "").trim().toLowerCase();
    const nombre = (b.nombre ?? "").trim();
    if (!correo.includes("@") || !nombre) return responder({ error: "Falta el correo o el nombre" }, 400);
    const { data, error } = await admin.auth.admin.createUser({
      email: correo, password: b.clave, email_confirm: true, user_metadata: { nombre },
    });
    if (error) return responder({ error: /already|registered|exists/i.test(error.message) ? "Ese correo ya tiene usuario: usa «Dar acceso»" : error.message }, 400);
    // El perfil lo crea el trigger nuevo_usuario; aquí se da el rol en este negocio
    const { error: e2 } = await admin.from("miembros").insert({ user_id: data.user.id, empresa_id: b.empresa_id, rol, caja: b.caja || null });
    if (e2) { await admin.auth.admin.deleteUser(data.user.id); return responder({ error: e2.message }, 500); }
    return responder({ ok: true, user_id: data.user.id });
  }

  if (b.accion === "clave") {
    const { data: m } = await admin.from("miembros").select("rol").eq("empresa_id", b.empresa_id).eq("user_id", b.user_id).maybeSingle();
    if (!m) return responder({ error: "Esa persona no está en este negocio" }, 404);
    const { data: pd } = await comoUsuario.rpc("puedo_crear_usuarios", { p_empresa: b.empresa_id, p_rol: m.rol });
    if (!pd) return responder({ error: "Solo el dueño cambia la clave de otro dueño" }, 403);
    const { error } = await admin.auth.admin.updateUserById(b.user_id, { password: b.clave });
    if (error) return responder({ error: error.message }, 400);
    return responder({ ok: true });
  }
  return responder({ error: "Acción desconocida" }, 400);
});
