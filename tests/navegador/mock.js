// Supabase simulado con estado, para probar las pantallas en Playwright
module.exports = function mock(page, o = {}) {
  const st = { llamadas: [], tasas: o.tasas || [], equipo: [{ user_id: 'u-d', nombre: 'José Guerrero', correo: 'jose@azullab.com', rol: 'dueno', caja: null, activo: true, ultima_entrada: null }],
    empresa: { id: 'E', tipo: o.tipo || 'farmacia', nombre: o.empresa || 'Azullab Farmacia', razon_social: 'Azullab Farmacia, C.A.', rif: 'J-00000001-0', domicilio: 'La Azulita', telefono: null, imprenta_serie: '00', talonario_serie: '01', talonario_desde: null, talonario_hasta: null, datos_confirmados: false },
    rol: o.rol || 'dueno', db: o.db || {} };
  const json = (r, b, status = 200) => r.fulfill({ status, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(b) });
  page.route('**/js/config.js', r => r.fulfill({ contentType: 'text/javascript', body: "window.CUADRE_CONFIG={url:'https://prueba.supabase.co',key:'pk'}" }));
  page.route('https://ve.dolarapi.com/**', r => json(r, { promedio: 300.5, fechaActualizacion: new Date().toISOString() }));
  page.route('https://prueba.supabase.co/**', async r => {
    const q = r.request(), u = new URL(q.url()), m = q.method(), p = u.pathname; let b = null; try { b = JSON.parse(q.postData() || 'null'); } catch (_) {}
    st.llamadas.push({ m, p: p + u.search, b });
    if (m === 'OPTIONS') return r.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' } });
    if (p === '/auth/v1/token') return json(r, { access_token: 'x.eyJzdWIiOiJ1LWQifQ.x', token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, refresh_token: 'r', user: { id: 'u-d', email: 'jose@azullab.com', aud: 'authenticated' } });
    if (p === '/auth/v1/user') return json(r, { id: 'u-d', email: 'jose@azullab.com', aud: 'authenticated' });
    if (p === '/rest/v1/rpc/mi_acceso') return json(r, [{ empresa_id: 'E', empresa: st.empresa.nombre, rol: st.rol, nombre: 'José Guerrero', caja: null, datos_confirmados: st.empresa.datos_confirmados }]);
    if (p === '/rest/v1/rpc/equipo') return json(r, st.equipo);
    if (p === '/rest/v1/rpc/dar_acceso') { if (b.p_correo.startsWith('nadie')) return json(r, { code: 'P0001', message: 'No hay ningún usuario con el correo ' + b.p_correo + '. Créalo con «Nuevo usuario»' }, 400); st.equipo.push({ user_id: 'u-' + st.equipo.length, nombre: b.p_correo.split('@')[0], correo: b.p_correo, rol: b.p_rol, caja: b.p_caja, activo: true }); return r.fulfill({ status: 204 }); }
    if (p === '/functions/v1/usuarios') { if (b.accion === 'crear') st.equipo.push({ user_id: 'u-' + st.equipo.length, nombre: b.nombre, correo: b.correo, rol: b.rol, caja: b.caja, activo: true, ultima_entrada: null }); return json(r, { ok: true }); }
    if (p === '/rest/v1/tasas_bcv' && m === 'GET') return json(r, st.tasas.slice().sort((a, c) => c.fecha.localeCompare(a.fecha)).slice(0, 1));
    if (p === '/rest/v1/tasas_bcv' && m === 'POST') { st.tasas = st.tasas.filter(t => t.fecha !== b.fecha).concat([b]); return json(r, [b], 201); }
    if (p === '/rest/v1/empresas' && m === 'GET') return json(r, st.empresa);
    if (p === '/rest/v1/empresas' && m === 'PATCH') { Object.assign(st.empresa, b); return json(r, st.empresa); }
    if (p === '/rest/v1/miembros' && m === 'PATCH') { const id = u.searchParams.get('user_id').slice(3), x = st.equipo.find(e => e.user_id === id); Object.assign(x, b); return json(r, [x]); }
    if (p === '/rest/v1/perfiles' && m === 'PATCH') { const id = u.searchParams.get('user_id').slice(3), x = st.equipo.find(e => e.user_id === id); x.nombre = b.nombre; return json(r, [x]); }
    if (o.rest) { const res = await o.rest(st, { m, p, u, b, q }); if (res) return json(r, res.body, res.status || 200); }
    return json(r, {});
  });
  return st;
};
