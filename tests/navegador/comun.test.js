const { chromium } = require('playwright'); const mock = require('./mock');
(async () => {
  const b = await chromium.launch(); let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
  const entrar = async (pg, sys) => { await pg.goto(`http://localhost:8765/${sys}.html`); await pg.waitForSelector('#loginForm'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]'); await pg.waitForFunction(() => (typeof S === 'object' && S.view !== 'login'), null, { timeout: 8000 }); };
  const txt = pg => pg.textContent('body');
  // ---------- Farmacia ----------
  { const ctx = await b.newContext(); const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message));
    const st = mock(pg); await entrar(pg, 'farmacia');
    await pg.waitForFunction(() => document.body.textContent.includes('300,50'), null, { timeout: 5000 }).catch(() => {});
    ok(st.tasas.length === 1 && st.tasas[0].tasa === 300.5, 'sin tasa de hoy, el dueño la carga sola al entrar');
    ok((await txt(pg)).includes('300,50'), 'la caja muestra la tasa de la base');
    await pg.evaluate(() => go('users')); await pg.waitForFunction(() => document.body.textContent.includes('jose@azullab.com'));
    ok((await txt(pg)).includes('Tú'), 'Usuarios: el equipo real con el dueño');
    await pg.click('[data-act="cq-nuevo"]'); await pg.fill('#cq-nom', 'Kevin Albarrán'); await pg.fill('#cq-correo', 'kevin@azullab.com'); await pg.fill('#cq-clave', 'clave1234'); await pg.selectOption('#cq-rol', 'cajero'); await pg.selectOption('#cq-caja', 'Caja 2');
    await pg.click('#cq-nuevo-f [type=submit]'); await pg.waitForFunction(() => document.body.textContent.includes('kevin@azullab.com'));
    const cr = st.llamadas.find(l => l.p === '/functions/v1/usuarios'); ok(cr && cr.b.rol === 'cajero' && cr.b.caja === 'Caja 2' && cr.b.empresa_id === 'E', 'Nuevo usuario llama a la función con rol y caja');
    await pg.click('[data-act="cq-editar"][data-i="1"]'); await pg.selectOption('#cq-rol', 'almacen'); await pg.fill('#cq-nom', 'Kevin A.'); await pg.click('#cq-editar-f [type=submit]');
    await pg.waitForFunction(() => document.body.textContent.includes('Kevin A.'));
    ok(st.equipo[1].rol === 'almacen', 'Editar cambia el rol en la base');
    await pg.click('[data-act="cq-acceso"]'); await pg.fill('#cq-correo', 'nadie@x.com'); await pg.click('#cq-acceso-f [type=submit]');
    await pg.waitForFunction(() => !document.getElementById('cq-err').hidden);
    ok((await pg.textContent('#cq-err')).includes('Créalo con'), 'Dar acceso a un correo sin usuario explica qué hacer');
    await pg.evaluate(() => closeModal());
    await pg.evaluate(() => go('config')); await pg.waitForSelector('#fx-dform');
    ok(await pg.inputValue('#fx-f-rif') === 'J-00000001-0', 'Configuración muestra el RIF de la base');
    await pg.fill('#fx-f-rif', 'J-123'); await pg.click('#fx-dform [type=submit]'); await pg.waitForTimeout(300);
    ok((await pg.textContent('#toast')).includes('J-12345678-9'), 'RIF mal escrito no se guarda');
    await pg.fill('#fx-f-rif', 'j41234567-8'); await pg.fill('#fx-f-talDesde', '1'); await pg.fill('#fx-f-talHasta', '100'); await pg.check('#fx-f-conf'); await pg.click('#fx-dform [type=submit]');
    await pg.waitForFunction(() => document.getElementById('toast').textContent.includes('ya puede facturar'));
    ok(st.empresa.rif === 'J-41234567-8' && st.empresa.datos_confirmados === true, 'guarda el RIF normalizado y confirmado');
    ok((await txt(pg)).includes('Confirmados'), 'la pantalla marca los datos como confirmados');
    ok(+st.empresa.talonario_desde === 1 && +st.empresa.talonario_hasta === 100, 'el rango del talonario de contingencia se guarda');
    await pg.evaluate(() => go('dashboard')); await pg.click('[data-act="tasa"]'); await pg.fill('#t-val', '412,30'); await pg.click('#tasaForm [type=submit]');
    await pg.waitForFunction(() => document.body.textContent.includes('412,30'));
    ok(st.tasas.find(t => t.tasa === 412.3 && t.fuente === 'Dueño'), 'el dueño escribe la tasa y se guarda en la base');
    ok(errs.length === 0, 'farmacia sin errores de JavaScript ' + errs.join(' | ')); await ctx.close(); }
  // ---------- Cajero: no ve Usuarios ni carga tasa ----------
  { const ctx = await b.newContext(); const pg = await ctx.newPage(); const st = mock(pg, { rol: 'cajero', tasas: [{ fecha: '2026-10-30', tasa: 280 }] });
    await entrar(pg, 'farmacia');
    ok(!st.llamadas.some(l => l.p === '/rest/v1/tasas_bcv' && l.m === 'POST'), 'el cajero no carga la tasa');
    ok((await txt(pg)).includes('280,00'), 'el cajero ve la última tasa de la base');
    ok(!(await pg.$('a[data-v="users"]')), 'el cajero no ve Usuarios'); await ctx.close(); }
  // ---------- Laboratorio y CrossFit ----------
  for (const [sys, emp] of [['laboratorio', 'Azullab Laboratorio'], ['crossfit', 'Azullab CrossFit']]) {
    const ctx = await b.newContext(); const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message));
    const st = mock(pg, { tipo: sys, empresa: emp }); await entrar(pg, sys);
    ok(await pg.$('a[data-v="users"]'), `${sys}: el dueño tiene Usuarios en el menú`);
    await pg.click('a[data-v="users"]'); await pg.waitForFunction(() => document.body.textContent.includes('jose@azullab.com'));
    const roles = await pg.$$eval('[data-act="cq-nuevo"]', x => x.length); ok(roles === 1, `${sys}: botón Nuevo usuario`);
    await pg.click('[data-act="cq-nuevo"]'); const ops = await pg.$$eval('#cq-rol option', x => x.map(o => o.value).join(','));
    ok(ops === (sys === 'crossfit' ? 'dueno,gerente,coach' : 'dueno,gerente,atencion,bioanalista,toma_muestras'), `${sys}: roles propios del negocio (${ops})`);
    ok(!(await pg.$('#cq-caja')), `${sys}: sin campo de caja`);
    await pg.evaluate(() => closeModal());
    if (sys === 'crossfit') ok(await pg.evaluate(() => RATE) === 300.5, 'crossfit: usa la tasa de la base');
    ok(errs.length === 0, `${sys} sin errores de JavaScript ` + errs.join(' | ')); await ctx.close();
  }
  await b.close(); process.exit(fallas ? 1 : 0);
})();
