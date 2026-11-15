// Usuarios → Permisos por rol: el dueño marca qué abre cada rol; el dueño siempre tiene todo (Supabase simulado)
const { chromium } = require('playwright'); const mock = require('./mock');
(async () => {
  const b = await chromium.launch(); let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
  const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Caracas' }).format(new Date());
  const T = { colecciones: [] };
  const rest = async (st, { m, p, u, b: body, q }) => {
    const uno = (q.headers()['accept'] || '').includes('vnd.pgrst.object');
    if (p === '/rest/v1/colecciones' && m === 'GET') { const n = (u.searchParams.get('nombre') || '').replace(/^eq\./, ''); const rs = T.colecciones.filter(c => !n || c.nombre === n); return { body: uno ? (rs[0] || null) : rs }; }
    if (p === '/rest/v1/colecciones' && m === 'POST') { if (body.nombre === 'permisos' && st.rol !== 'dueno') return { status: 403, body: { message: 'new row violates row-level security policy' } };
      T.colecciones = T.colecciones.filter(c => c.nombre !== body.nombre).concat([body]); return { body: uno ? body : [body] }; }
    if (m === 'GET' && p.startsWith('/rest/v1/') && !p.includes('/rpc/')) return { body: uno ? null : [] };
  };
  const entrar = async (rol) => {
    const ctx = await b.newContext(); const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message));
    const st = mock(pg, { rol, tasas: [{ fecha: hoy, tasa: 100 }], rest });
    await pg.goto('http://localhost:8765/farmacia.html'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]');
    await pg.waitForFunction(() => typeof S === 'object' && S.view !== 'login', null, { timeout: 8000 }); await pg.waitForTimeout(300);
    return { ctx, pg, st, errs };
  };
  const menu = pg => pg.evaluate(() => [...document.querySelectorAll('nav a[data-v]')].map(a => a.dataset.v));

  // 1. El dueño ve la lista con casillas y la guarda
  { const { ctx, pg, st, errs } = await entrar('dueno');
    await pg.evaluate(() => go('users')); await pg.waitForSelector('input[data-perm]');
    const txt = await pg.textContent('main');
    ok(txt.includes('Permisos por rol') && txt.includes('Siempre'), 'Usuarios trae la lista de permisos por rol; el dueño: siempre');
    ok(await pg.$('input[data-perm="caja"][data-rol="cajero"]:checked') && !(await pg.$('input[data-perm="fiscal"][data-rol="cajero"]:checked')), 'sin cambios, cada rol tiene lo de siempre (el cajero: solo la caja)');
    ok(!(await pg.$('input[data-perm="compras"][data-rol="cajero"]')) && !(await pg.$('input[data-perm="finanzas"][data-rol="regente"]')), 'lo que la base no le deja a un rol no se ofrece (raya)');
    ok(!(await pg.$('input[data-perm][data-rol="dueno"]')), 'al dueño no se le quita nada');
    await pg.check('input[data-perm="fiscal"][data-rol="cajero"]'); await pg.check('input[data-perm="facturas"][data-rol="cajero"]');
    await pg.uncheck('input[data-perm="compras"][data-rol="regente"]'); await pg.uncheck('input[data-perm="nomina"][data-rol="gerente"]');
    await pg.click('[data-act="cq-perm-ok"]'); await pg.waitForFunction(() => document.getElementById('toast').textContent.includes('Permisos guardados'), null, { timeout: 5000 }).catch(() => {});
    const g = T.colecciones.find(c => c.nombre === 'permisos');
    ok(g && g.datos.cajero.join() === 'caja,fiscal,facturas' && !g.datos.regente.includes('compras') && !g.datos.gerente.includes('nomina') && !('dueno' in g.datos), 'guarda la lista por rol en la base, sin el dueño');
    ok((await menu(pg)).includes('payroll') && (await menu(pg)).includes('purchases'), 'el dueño sigue viendo todo');
    ok(errs.length === 0, 'dueño: sin errores de JavaScript ' + errs.join(' | ')); await ctx.close(); }

  // 2. Lo marcado vale para cada rol al entrar
  { const { ctx, pg, errs } = await entrar('cajero');
    const m = await menu(pg);
    ok(m.includes('pos') && m.includes('fiscal') && m.includes('docs') && !m.includes('purchases') && !m.includes('users'), 'el cajero ve la caja, el Módulo fiscal y Facturas que le dio el dueño, y nada más');
    ok(errs.length === 0, 'cajero: sin errores de JavaScript ' + errs.join(' | ')); await ctx.close(); }
  { const { ctx, pg, errs } = await entrar('regente');
    ok(!(await menu(pg)).includes('purchases'), 'al regente se le quitó Compras: no sale en el menú');
    await pg.evaluate(() => go('purchases'));
    ok(await pg.evaluate(() => S.view) !== 'purchases' && (await pg.textContent('#toast')).includes('no tiene acceso'), 'y si intenta abrirla, no entra');
    ok(errs.length === 0, 'regente: sin errores de JavaScript ' + errs.join(' | ')); await ctx.close(); }
  { const { ctx, pg, errs } = await entrar('gerente');
    const m = await menu(pg);
    ok(!m.includes('payroll') && !m.includes('employees') && m.includes('finance'), 'al gerente se le quitó Nómina; lo demás lo sigue viendo');
    await pg.evaluate(() => go('users')); await pg.waitForSelector('input[data-perm]');
    ok(await pg.$('input[data-perm][disabled]') && !(await pg.$('[data-act="cq-perm-ok"]')), 'el gerente ve los permisos pero no los cambia');
    ok(errs.length === 0, 'gerente: sin errores de JavaScript ' + errs.join(' | ')); await ctx.close(); }

  // 3. Volver a lo de siempre
  { const { ctx, pg } = await entrar('dueno');
    await pg.evaluate(() => go('users')); await pg.waitForSelector('[data-act="cq-perm-def"]'); await pg.click('[data-act="cq-perm-def"]');
    await pg.waitForFunction(() => document.getElementById('toast').textContent.includes('de siempre'), null, { timeout: 5000 }).catch(() => {});
    ok(JSON.stringify(T.colecciones.find(c => c.nombre === 'permisos').datos) === '{}' && !(await pg.$('input[data-perm="fiscal"][data-rol="cajero"]:checked')), '«Volver a lo de siempre» deja cada rol como venía');
    await ctx.close(); }
  await b.close(); process.exit(fallas ? 1 : 0);
})();
