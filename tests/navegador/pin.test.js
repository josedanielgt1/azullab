// Equipo registrado y entrada con PIN, con y sin internet (Supabase simulado)
const { chromium } = require('playwright'); const mock = require('./mock');
(async () => {
  const b = await chromium.launch(); let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
  const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Caracas' }).format(new Date());
  const ctx = await b.newContext(); const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message));
  const st = mock(pg, { tasas: [{ fecha: hoy, tasa: 100 }], empresaExtra: { talonario_desde: 1, talonario_hasta: 50 } });
  const adentro = () => pg.waitForFunction(() => typeof S === 'object' && S.view !== 'login', null, { timeout: 10000 });
  const enLogin = () => pg.waitForFunction(() => typeof S === 'object' && S.view === 'login', null, { timeout: 10000 });
  const salir = async () => { await pg.evaluate(() => go('users')); await pg.click('[data-act="logout"]'); await enLogin(); await pg.waitForTimeout(200); };
  const pin = async (p) => { await pg.click('[data-act="cuadre-quien"]'); await pg.fill('#lpin', p); await pg.click('#pinForm [type=submit]'); };
  const guardado = () => pg.evaluate(() => JSON.parse(localStorage.getItem('cuadre.pines.farmacia') || '{}'));

  await pg.goto('http://localhost:8765/farmacia.html');
  ok(!(await pg.$('#cuadre-pin')), 'sin equipo registrado: entrada normal con correo y clave');
  await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]'); await adentro();

  // Registrar el equipo y crear el PIN
  await pg.evaluate(() => go('users')); await pg.fill('#eq-nom', 'Caja 1'); await pg.click('#eq-reg-f [type=submit]');
  ok((await pg.evaluate(() => JSON.parse(localStorage.getItem('cuadre.equipo.farmacia')))).nombre === 'Caja 1', 'el dueño registra el equipo «Caja 1»');
  await pg.click('[data-act="eq-mi-pin"]'); await pg.fill('#eq-p1', '1234'); await pg.fill('#eq-p2', '1234'); await pg.click('#eq-pin-f [type=submit]');
  await pg.waitForFunction(() => !document.getElementById('cq-err').hidden);
  ok((await pg.textContent('#cq-err')).includes('fácil'), 'un PIN seguido (1234) no se acepta');
  await pg.fill('#eq-p1', '2580'); await pg.fill('#eq-p2', '2580'); await pg.click('#eq-pin-f [type=submit]');
  await pg.waitForFunction(() => Object.keys(JSON.parse(localStorage.getItem('cuadre.pines.farmacia') || '{}')).length === 1);
  const r = Object.values(await guardado())[0];
  ok(r && r.nombre === 'José Guerrero' && r.acceso.rol === 'dueno', 'queda el PIN de José con su rol');
  ok(!JSON.stringify(r).includes('x.eyJzdWIiOiJ1LWQifQ.x') && !JSON.stringify(r).includes('2580'), 'ni la sesión ni el PIN quedan legibles en el equipo');

  // Salir no cierra la sesión en el servidor: queda guardada para el PIN
  const nLogout = () => st.llamadas.filter(l => l.p.startsWith('/auth/v1/logout')).length;
  await salir();
  ok(nLogout() === 0 && await pg.evaluate(() => !localStorage.getItem('cuadre.sesion')), 'salir en un equipo con PIN guarda la sesión cifrada sin cerrarla en el servidor');
  ok((await pg.textContent('body')).includes('¿Quién entra?'), 'la entrada muestra «¿Quién entra?» con la gente del equipo');

  // PIN errado y correcto
  await pin('0000'); await pg.waitForFunction(() => document.body.textContent.includes('PIN incorrecto'));
  ok((await pg.textContent('body')).includes('quedan 4 intentos'), 'PIN errado: avisa cuántos intentos quedan');
  const nAcc = st.llamadas.filter(l => l.p === '/rest/v1/rpc/mi_acceso').length;
  await pg.fill('#lpin', '2580'); await pg.click('#pinForm [type=submit]'); await adentro();
  ok(st.llamadas.filter(l => l.p === '/rest/v1/rpc/mi_acceso').length > nAcc, 'con internet, el PIN abre y la base confirma el acceso');
  ok((await guardado())[r.uid].intentos === 0, 'al acertar, los intentos vuelven a cero');

  // Recargar no pide el PIN otra vez
  await pg.reload(); await adentro();
  ok(true, 'recargar la página no pide el PIN de nuevo');

  // Sin internet
  await salir(); await ctx.setOffline(true);
  await pg.evaluate(() => { window.dispatchEvent(new Event('offline')); render(); });
  ok((await pg.textContent('body')).includes('Sin internet'), 'sin internet: la entrada lo avisa y ofrece el PIN');
  await pin('2580'); await adentro();
  ok(await pg.evaluate(() => Cuadre.acceso.sinConexion === true && Cuadre.acceso.rol === 'dueno'), 'sin internet: entra con el PIN y su rol guardado');
  await ctx.setOffline(false); await pg.evaluate(() => window.dispatchEvent(new Event('online')));
  await pg.waitForFunction(() => Cuadre.acceso && !Cuadre.acceso.sinConexion, null, { timeout: 5000 }).catch(() => {});
  ok(await pg.evaluate(() => !Cuadre.acceso.sinConexion), 'al volver internet, la base confirma el acceso');

  // 5 errores bloquean; la clave desbloquea
  await salir();
  await pg.click('[data-act="cuadre-quien"]');
  for (let i = 0; i < 5; i++) { await pg.fill('#lpin', '1111'); await pg.click('#pinForm [type=submit]'); await pg.waitForTimeout(600); if (!(await pg.$('#lpin'))) break; }
  ok((await pg.textContent('body')).includes('Bloqueado: entra con tu clave') && await pg.$eval('[data-act="cuadre-quien"]', x => x.disabled), '5 PIN errados bloquean a esa persona en este equipo');
  // La entrada con la clave abre otra sesión (otro session_id en el token)
  const tok2 = 'x.' + Buffer.from(JSON.stringify({ sub: 'u-d', session_id: 'clave-2' })).toString('base64url') + '.x';
  await pg.route('https://prueba.supabase.co/auth/v1/token**', r2 => r2.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' },
    body: JSON.stringify({ access_token: tok2, token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, refresh_token: 'r2', user: { id: 'u-d', email: 'jose@azullab.com', aud: 'authenticated' } }) }));
  await pg.click('[data-act="cuadre-con-clave"]'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]'); await adentro();
  await pg.unroute('https://prueba.supabase.co/auth/v1/token**');
  ok((await guardado())[r.uid].intentos === 0, 'entrar con la clave lo desbloquea');
  await salir();
  ok(nLogout() === 1, 'la sesión abierta con la clave sí se cierra (solo en este equipo); la del PIN sigue guardada');
  ok(st.llamadas.filter(l => l.p.startsWith('/auth/v1/logout')).every(l => l.p.includes('scope=local')), 'cerrar sesión no saca a la persona de sus otros equipos');

  // 7 días sin conexión vencen el PIN
  await pg.evaluate(() => { const t = JSON.parse(localStorage.getItem('cuadre.pines.farmacia')); Object.values(t)[0].ultima = Date.now() - 8 * 864e5; localStorage.setItem('cuadre.pines.farmacia', JSON.stringify(t)); render(); });
  ok((await pg.textContent('body')).includes('Vencido: entra con tu clave'), 'pasados 7 días sin conexión el PIN vence');

  // App recién abierta (pestaña nueva): pide el PIN
  await pg.evaluate(() => { const t = JSON.parse(localStorage.getItem('cuadre.pines.farmacia')); Object.values(t)[0].ultima = Date.now(); localStorage.setItem('cuadre.pines.farmacia', JSON.stringify(t)); render(); });
  await pin('2580'); await adentro();
  const p2 = await ctx.newPage(); mock(p2, { tasas: [{ fecha: hoy, tasa: 100 }] }); await p2.goto('http://localhost:8765/farmacia.html'); await p2.waitForTimeout(800);
  ok((await p2.textContent('body')).includes('¿Quién entra?'), 'al abrir la app de nuevo, pide el PIN (no entra solo)');
  ok(await pg.evaluate(() => !!localStorage.getItem('cuadre.sesion')), 'y no le cierra la sesión a la pestaña que está en uso');
  await p2.close();

  // Persona nueva en el equipo: al entrar con su clave se le ofrece crear el PIN
  await salir(); await pg.click('[data-act="cuadre-con-clave"]');
  await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena');
  await pg.evaluate(() => { const t = JSON.parse(localStorage.getItem('cuadre.pines.farmacia')); localStorage.setItem('cuadre.pines.farmacia', '{}'); window.__t = t; });
  await pg.click('#loginForm [type=submit]'); await pg.waitForSelector('#pinNuevo');
  ok((await pg.textContent('body')).includes('Crea tu PIN para este equipo'), 'quien entra con su clave en un equipo registrado puede crear su PIN');
  await pg.fill('#pin1', '4826'); await pg.fill('#pin2', '4862'); await pg.click('#pinNuevo [type=submit]'); await pg.waitForTimeout(200);
  ok((await pg.textContent('#login-err')).includes('no son iguales'), 'si los dos PIN no son iguales, lo dice');
  await pg.fill('#pin2', '4826'); await pg.click('#pinNuevo [type=submit]'); await adentro();
  ok(Object.keys(await guardado()).length === 1, 'PIN creado y adentro');

  // Quitarle el acceso: el PIN deja de servir con internet
  await salir();
  st.rol = null; await pg.route('https://prueba.supabase.co/rest/v1/rpc/mi_acceso', r2 => r2.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: '[]' }));
  await pin('4826');
  await pg.waitForFunction(() => localStorage.getItem('cuadre.pines.farmacia') === '{}', null, { timeout: 8000 }).catch(() => {}); await pg.waitForFunction(() => document.body.textContent.includes('ya no sirve'), null, { timeout: 8000 }).catch(() => {});
  ok((await pg.textContent('body')).includes('ya no sirve') && Object.keys(await guardado()).length === 0, 'si le quitan el acceso, su PIN deja de servir y se borra del equipo');

  ok(errs.length === 0, 'sin errores en la página' + (errs.length ? ': ' + errs.join(' | ').slice(0, 300) : ''));
  await b.close(); process.exit(fallas ? 1 : 0);
})();
