// Farmacia sin internet: vende con el talonario de contingencia y sube al volver la conexión (Supabase simulado)
const { chromium } = require('playwright'); const mock = require('./mock');
(async () => {
  const b = await chromium.launch(); let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
  const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Caracas' }).format(new Date());
  const T = { rpc: [], docs: [] };
  const rest = async (st, { m, p, b: body, q }) => {
    const uno = (q.headers()['accept'] || '').includes('vnd.pgrst.object');
    if (p === '/rest/v1/productos' && m === 'GET') return { body: [{ id: 1, empresa_id: 'E', codigo: '111', codigos_alt: [], nombre: 'Losartán 50 mg', principio_activo: 'Losartán', iva: 'E', costo: 2, margen: 50, precio: 3, por_lote: false, minimo: 5, rx: false, controlado: false, historial: [] }] };
    if (p === '/rest/v1/lotes' && m === 'GET') return { body: [{ id: 9, empresa_id: 'E', producto_id: 1, lote: 'A1', vence: '2028-01-01', cantidad: 10, costo: 2, precio: null }] };
    if (p === '/rest/v1/documentos' && m === 'GET') return { body: uno ? null : T.docs };
    if (p === '/rest/v1/rpc/vender') { T.rpc.push(body); const d = { id: 'c-' + body.p_numero, empresa_id: 'E', tipo: 'FAC', origen: body.p_origen, numero: body.p_numero, fecha: body.p_fecha, tasa: 100, total: 300, total_usd: 3, igtf: 0, cliente_rif: 'V-00000000', cliente_nombre: 'Consumidor final', documento_lineas: [], documento_pagos: [] }; T.docs.push(d); return { body: d }; }
    if (m === 'GET' && p.startsWith('/rest/v1/') && !p.includes('rpc')) return { body: uno ? null : [] };
  };
  const ctx = await b.newContext(); const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message));
  mock(pg, { tasas: [{ fecha: hoy, tasa: 100 }], rest, empresaExtra: { talonario_desde: 1, talonario_hasta: 50, datos_confirmados: true } });
  await pg.goto('http://localhost:8765/farmacia.html'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]');
  await pg.waitForFunction(() => (typeof S === 'object' && S.view !== 'login') && P.length === 1, null, { timeout: 8000 });
  ok(await pg.evaluate(() => !!localStorage.getItem('cuadre.farmacia.catalogo')), 'el catálogo queda copiado en el equipo');
  ok(await pg.evaluate(() => FX.n.tal) === 1, 'el talonario empieza en el primer número libre');
  // Se va el internet
  await ctx.setOffline(true); await pg.waitForTimeout(300);
  ok(await pg.evaluate(() => S.online === false), 'el sistema detecta solo que no hay internet');
  await pg.evaluate(() => go('pos')); await pg.click('[data-act="add"][data-id="1"]'); await pg.click('[data-act="checkout"]'); await pg.click('[data-act="addpay"]');
  ok(await pg.$('#contnum'), 'el cobro pide el control del talonario de contingencia');
  await pg.click('[data-act="emit"]'); await pg.waitForTimeout(500);
  const cola = await pg.evaluate(() => JSON.parse(localStorage.getItem('cuadre.farmacia.cola') || '[]'));
  ok(cola.length === 1 && cola[0].numero === 1 && cola[0].items[0].cantidad === 1, 'la venta queda guardada en la cola del equipo');
  ok((await pg.textContent('#modal')).includes('C-00000001'), 'el ticket sale con el número del talonario');
  ok(await pg.evaluate(() => P[0].stock) === 9, 'la existencia baja en la pantalla');
  ok(T.rpc.length === 0, 'nada fue a la base mientras no había internet');
  await pg.evaluate(() => closeModal());
  // Vuelve el internet
  await ctx.setOffline(false); await pg.waitForFunction(() => !JSON.parse(localStorage.getItem('cuadre.farmacia.cola') || '[]').length, null, { timeout: 8000 }).catch(() => {});
  const v = T.rpc[0];
  ok(v && v.p_origen === 'contingencia' && v.p_numero === 1 && v.p_fecha, 'al volver internet la venta sube sola como contingencia, con su número y fecha');
  ok(await pg.evaluate(() => JSON.parse(localStorage.getItem('cuadre.farmacia.cola') || '[]').length) === 0, 'y la cola queda vacía');
  ok(await pg.evaluate(() => S.online === true), 'el sistema vuelve a «En línea»');
  ok(errs.length === 0, 'sin errores de JavaScript ' + errs.join(' | ').slice(0, 300));
  await b.close(); process.exit(fallas ? 1 : 0);
})();
