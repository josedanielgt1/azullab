// Un cliente registrado sin internet sube al volver la conexión, y no se pierde si se recarga antes (Supabase simulado)
const { chromium } = require('playwright'); const mock = require('./mock');
(async () => {
  const b = await chromium.launch(); let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
  const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Caracas' }).format(new Date());
  const T = { clientes: [], seq: 1 };
  const rest = async (st, { m, p, b: body, q }) => {
    const uno = (q.headers()['accept'] || '').includes('vnd.pgrst.object'), out = x => ({ body: uno ? (Array.isArray(x) ? (x[0] ?? null) : x) : x });
    if (p === '/rest/v1/clientes' && m === 'GET') return out(T.clientes);
    if (p === '/rest/v1/clientes' && m === 'POST') { const r = { id: T.seq++, visitas: 0, total_usd: 0, puntos: 0, ultima: null, ...body }; T.clientes.push(r); return out(r); }
    if (m === 'GET' && p.startsWith('/rest/v1/') && !p.includes('/rpc/')) return { body: [] };
  };
  const ctx = await b.newContext(); const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message));
  const st = mock(pg, { tasas: [{ fecha: hoy, tasa: 100 }], rest, empresaExtra: { talonario_desde: 1, talonario_hasta: 50 } });
  const posts = () => st.llamadas.filter(l => l.p.startsWith('/rest/v1/clientes') && l.m === 'POST');
  await pg.goto('http://localhost:8765/farmacia.html'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'x'); await pg.click('#loginForm [type=submit]');
  await pg.waitForFunction(() => S.view !== 'login'); await pg.waitForTimeout(500);
  const nuevo = async (ci, n) => { await pg.evaluate(() => go('clients')); await pg.click('[data-act="clinew"]'); await pg.fill('#cl-ci', ci); await pg.fill('#cl-n', n); await pg.click('#cliForm [type=submit]'); await pg.waitForTimeout(400); };

  // 1. Sin internet: el cliente queda en el equipo y la franja lo cuenta
  await ctx.setOffline(true); await pg.evaluate(() => window.dispatchEvent(new Event('offline')));
  await nuevo('V-12345678', 'María Prueba');
  ok(posts().length === 0, 'sin internet no se intenta guardar en la base');
  ok((await pg.textContent('#cuadre-pendientes').catch(() => '')).includes('1 cliente sin subir'), 'la franja avisa «1 cliente sin subir»');
  ok(await pg.evaluate(() => (JSON.parse(localStorage.getItem('cuadre.farmacia.cambios') || '{}').clientes || []).some(c => c.name === 'María Prueba')), 'el cliente queda guardado en el equipo');

  // 2. Vuelve internet: sube solo
  await ctx.setOffline(false); await pg.evaluate(() => window.dispatchEvent(new Event('online')));
  await pg.waitForFunction(() => !document.getElementById('cuadre-pendientes'), null, { timeout: 8000 }).catch(() => {});
  ok(T.clientes.some(c => c.nombre === 'María Prueba' && c.cedula_rif === 'V-12345678'), 'al volver internet, el cliente sube solo a la base');
  ok(!(await pg.$('#cuadre-pendientes')) && await pg.evaluate(() => !localStorage.getItem('cuadre.farmacia.cambios')), 'y la franja y la copia del equipo se quitan');

  // 3. Otro cliente sin internet; la subida falla y la página se recarga antes de que suba
  await ctx.setOffline(true); await pg.evaluate(() => window.dispatchEvent(new Event('offline')));
  await nuevo('V-87654321', 'Pedro Prueba');
  await pg.route('https://prueba.supabase.co/rest/v1/clientes**', r => r.request().method() === 'POST' ? r.abort('failed') : r.fallback());
  await ctx.setOffline(false); await pg.evaluate(() => window.dispatchEvent(new Event('online'))); await pg.waitForTimeout(1500);
  ok(!T.clientes.some(c => c.nombre === 'Pedro Prueba'), '(la subida falló: el cliente sigue sin subir)');
  await pg.unroute('https://prueba.supabase.co/rest/v1/clientes**');
  await pg.reload(); await pg.waitForFunction(() => typeof S === 'object' && S.view !== 'login', null, { timeout: 10000 });
  await pg.waitForFunction(() => !document.getElementById('cuadre-pendientes'), null, { timeout: 8000 }).catch(() => {});
  ok(T.clientes.some(c => c.nombre === 'Pedro Prueba'), 'aunque se recargó la página, al entrar el cliente vuelve y sube');
  ok(T.clientes.filter(c => c.nombre === 'María Prueba').length === 1, 'sin repetir el que ya había subido');

  // 4. El respaldo en carpeta incluye los clientes sin subir
  await pg.evaluate(() => { window.__archivos = {};
    Cuadre.respaldo.manija = { name: 'R', queryPermission: async () => 'granted', requestPermission: async () => 'granted',
      getFileHandle: async n => ({ createWritable: async () => ({ write: async d => { window.__archivos[n] = d; }, close: async () => {} }) }), removeEntry: async n => { delete window.__archivos[n]; } }; });
  await ctx.setOffline(true); await pg.evaluate(() => window.dispatchEvent(new Event('offline')));
  await nuevo('V-11223344', 'Ana Prueba');
  await pg.waitForFunction(() => window.__archivos['cuadre-farmacia-pendientes.json'], null, { timeout: 5000 }).catch(() => {});
  ok(await pg.evaluate(() => { const d = JSON.parse(window.__archivos['cuadre-farmacia-pendientes.json'] || '{}'); return (d.cambios && d.cambios.clientes || []).some(c => c.name === 'Ana Prueba'); }), 'el cliente sin subir también queda en la carpeta de respaldo');
  await ctx.setOffline(false); await pg.evaluate(() => window.dispatchEvent(new Event('online')));
  await pg.waitForFunction(() => !window.__archivos['cuadre-farmacia-pendientes.json'], null, { timeout: 8000 }).catch(() => {});
  ok(T.clientes.some(c => c.nombre === 'Ana Prueba') && await pg.evaluate(() => !window.__archivos['cuadre-farmacia-pendientes.json']), 'al subir, se borra de la carpeta');

  ok(errs.length === 0, 'sin errores en la página' + (errs.length ? ': ' + errs.join(' | ').slice(0, 300) : ''));
  await b.close(); process.exit(fallas ? 1 : 0);
})();
