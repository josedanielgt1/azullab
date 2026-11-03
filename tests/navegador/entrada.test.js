const { chromium } = require('playwright');
const ROL = { farmacia: 'cajero', laboratorio: 'bioanalista', crossfit: 'coach' };
(async () => {
  const b = await chromium.launch();
  let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
  for (const sys of ['farmacia', 'laboratorio', 'crossfit']) {
    const ctx = await b.newContext(); const pg = await ctx.newPage();
    const errs = []; pg.on('pageerror', e => errs.push(e.message));
    let sinRol = false;
    await pg.route('**/js/config.js', r => r.fulfill({ contentType: 'text/javascript', body: "window.CUADRE_CONFIG={url:'https://prueba.supabase.co',key:'pk'}" }));
    await pg.route('https://prueba.supabase.co/**', async r => {
      const u = r.request().url();
      if (u.includes('/auth/v1/token')) {
        const d = JSON.parse(r.request().postData());
        if (d.password !== 'clave-buena') return r.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ error: 'invalid_grant', error_description: 'Invalid login credentials', message: 'Invalid login credentials' }) });
        return r.fulfill({ contentType: 'application/json', body: JSON.stringify({ access_token: 'x.eyJzdWIiOiIxIn0.x', token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, refresh_token: 'r', user: { id: '1', email: d.email, aud: 'authenticated' } }) });
      }
      if (u.includes('/rpc/mi_acceso')) return r.fulfill({ contentType: 'application/json', body: JSON.stringify(sinRol ? [] : [{ empresa_id: 'e', empresa: 'X', rol: ROL[sys], nombre: 'José Guerrero', caja: null, datos_confirmados: false }]) });
      if (u.includes('/logout')) return r.fulfill({ status: 204 });
      r.fulfill({ status: 200, contentType: 'application/json', body: '{}' });
    });
    await pg.goto(`http://localhost:8765/${sys}.html`);
    await pg.waitForSelector('#loginForm');
    ok(!(await pg.$('.roles')), `${sys}: ya no hay botones para escoger el rol`);
    await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'mala'); await pg.click('#loginForm [type=submit]');
    await pg.waitForFunction(() => !document.getElementById('login-err').hidden);
    ok((await pg.textContent('#login-err')).includes('Correo o clave incorrectos'), `${sys}: clave mala → "Correo o clave incorrectos"`);
    sinRol = true; await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]');
    await pg.waitForFunction(() => /rol en este negocio/.test(document.getElementById('login-err').textContent));
    ok(await pg.$('#loginForm'), `${sys}: usuario sin rol no entra`);
    sinRol = false; await pg.click('#loginForm [type=submit]');
    await pg.waitForFunction(() => !document.getElementById('loginForm'), null, { timeout: 5000 });
    const t = await pg.textContent('body');
    ok(t.includes('José Guerrero'), `${sys}: entra con su nombre`);
    // Recargar: la sesión guardada entra sola
    await pg.reload(); await pg.waitForFunction(() => !document.getElementById('loginForm'), null, { timeout: 5000 }).catch(() => {});
    ok(!(await pg.$('#loginForm')), `${sys}: al recargar entra solo con la sesión guardada`);
    // Enlace directo sin sesión no entra
    const ctx2 = await b.newContext(); const p2 = await ctx2.newPage();
    await p2.route('**/js/config.js', r => r.fulfill({ contentType: 'text/javascript', body: "window.CUADRE_CONFIG={url:'https://prueba.supabase.co',key:'pk'}" }));
    await p2.goto(`http://localhost:8765/${sys}.html#config`); await p2.waitForTimeout(800);
    ok(await p2.$('#loginForm'), `${sys}: #config sin sesión muestra la entrada`);
    await ctx2.close();
    ok(errs.length === 0, `${sys}: sin errores de JavaScript ${errs.join(' | ')}`);
    await ctx.close();
  }
  // Sesión guardada de otro usuario (farmacéutico) que tarda en abrir mientras el dueño entra con su correo: gana el dueño
  { const c3 = await b.newContext(); const p3 = await c3.newPage(); let entro = false;
    await p3.route('**/js/config.js', r => r.fulfill({ contentType: 'text/javascript', body: "window.CUADRE_CONFIG={url:'https://prueba.supabase.co',key:'pk'}" }));
    await p3.addInitScript(() => { try { localStorage.setItem('cuadre.sesion', JSON.stringify({ access_token: 'x.eyJzdWIiOiJ2aWVqbyJ9.x', token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, refresh_token: 'r', user: { id: 'viejo', aud: 'authenticated' } })); } catch (_) {} });
    const mock = require('./mock');
    mock(p3, { rest: async () => null, miAcceso: async () => { if (!entro) { await new Promise(r => setTimeout(r, 700)); return [{ empresa_id: 'E', empresa: 'Azullab Farmacia', rol: 'regente', nombre: 'Farmacéutico de prueba', caja: null }]; }
      await new Promise(r => setTimeout(r, 1500)); return [{ empresa_id: 'E', empresa: 'Azullab Farmacia', rol: 'dueno', nombre: 'José Guerrero', caja: null }]; } });
    p3.on('request', q => { if (q.url().includes('/auth/v1/token')) entro = true; });
    await p3.goto('http://localhost:8765/farmacia.html', { waitUntil: 'domcontentloaded' }); await p3.waitForSelector('#loginForm');
    await p3.fill('#lu', 'jose@azullab.com'); await p3.fill('#lp', 'clave-buena'); await p3.click('#loginForm [type=submit]');
    await p3.waitForTimeout(3500);
    ok(await p3.evaluate(() => S.role === 'Dueño' && S.user === 'José Guerrero'), 'entrar con correo y clave gana sobre la sesión guardada de otro usuario');
    await c3.close(); }
  // Sin configurar
  const p = await (await b.newContext()).newPage();
  await p.route('**/js/config.js', r => r.fulfill({ contentType: 'text/javascript', body: "window.CUADRE_CONFIG={url:'',key:''}" }));
  await p.goto('http://localhost:8765/farmacia.html'); await p.waitForSelector('#loginForm');
  ok((await p.textContent('body')).includes('Falta conectar la base de datos'), 'sin config.js: avisa que falta conectar');
    await b.close(); process.exit(fallas ? 1 : 0);
})();
