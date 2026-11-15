// Farmacia sin internet: la máquina fiscal (simulada) sigue facturando y la venta sube al volver la conexión.
// Sin la impresora configurada, la farmacia no factura (no hay imprenta ni talonario). Supabase simulado.
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
    if (p === '/rest/v1/rpc/vender_impresa') { T.rpc.push(body); return { body: { id: 'i-' + body.p_numero, medio: 'maquina', numero_fiscal: body.p_numero } }; }
    if (p === '/rest/v1/rpc/vender') { T.rpc.push(body); const d = { id: 'c-' + body.p_numero, empresa_id: 'E', tipo: 'FAC', origen: body.p_origen, numero: body.p_numero, fecha: body.p_fecha, tasa: 100, total: 300, total_usd: 3, igtf: 0, cliente_rif: 'V-00000000', cliente_nombre: 'Consumidor final', documento_lineas: [], documento_pagos: [] }; T.docs.push(d); return { body: d }; }
    if (m === 'GET' && p.startsWith('/rest/v1/') && !p.includes('rpc')) return { body: uno ? null : [] };
  };
  const ctx = await b.newContext(); const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message));
  mock(pg, { tasas: [{ fecha: hoy, tasa: 100 }], rest, empresaExtra: { datos_confirmados: true } });
  await pg.goto('http://localhost:8765/farmacia.html'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]');
  await pg.waitForFunction(() => (typeof S === 'object' && S.view !== 'login') && P.length === 1, null, { timeout: 8000 });
  ok(await pg.evaluate(() => !!localStorage.getItem('cuadre.farmacia.catalogo')), 'el catálogo queda copiado en el equipo');
  // Se va el internet
  await ctx.setOffline(true); await pg.waitForTimeout(300);
  ok(await pg.evaluate(() => S.online === false), 'el sistema detecta solo que no hay internet');
  await pg.evaluate(() => go('pos')); await pg.click('[data-act="add"][data-id="1"]'); await pg.click('[data-act="checkout"]'); await pg.click('[data-act="addpay"]');
  ok(!(await pg.$('#contnum')) && (await pg.textContent('#modal')).includes('Emitir factura fiscal'), 'el cobro no pide talonario: la factura sale por la máquina fiscal');
  await pg.click('[data-act="emit"]'); await pg.waitForTimeout(500);
  const cola = await pg.evaluate(() => JSON.parse(localStorage.getItem('cuadre.farmacia.cola') || '[]'));
  ok(cola.length === 1 && cola[0].numero === 900000001 && cola[0].maquina === 'Z7C0012345' && cola[0].items[0].cantidad === 1, 'la impresora imprime sin internet y la venta queda en la cola con su número fiscal');
  ok((await pg.textContent('#modal')).includes('900000001') && !(await pg.textContent('#modal')).includes('TALONARIO'), 'el ticket sale con el número de la máquina, sin talonario');
  ok(await pg.evaluate(() => P[0].stock) === 9, 'la existencia baja en la pantalla');
  ok(T.rpc.length === 0, 'nada fue a la base mientras no había internet');
  await pg.evaluate(() => closeModal());
  // Vuelve el internet
  await ctx.setOffline(false); await pg.waitForFunction(() => !JSON.parse(localStorage.getItem('cuadre.farmacia.cola') || '[]').length, null, { timeout: 8000 }).catch(() => {});
  const v = T.rpc[0];
  ok(v && v.p_numero === 900000001 && v.p_registro === 'Z7C0012345' && v.p_fecha && !('p_origen' in v), 'al volver internet la venta sube sola con su número fiscal (vender_impresa), no como contingencia');
  ok(await pg.evaluate(() => JSON.parse(localStorage.getItem('cuadre.farmacia.cola') || '[]').length) === 0, 'y la cola queda vacía');
  ok(await pg.evaluate(() => S.online === true), 'el sistema vuelve a «En línea»');
  ok(errs.length === 0, 'sin errores de JavaScript ' + errs.join(' | ').slice(0, 300));
  await ctx.close();
  // Sin la impresora configurada: la farmacia no factura y el Módulo fiscal lo dice
  { const c2 = await b.newContext(); const p2 = await c2.newPage(); const e2 = []; p2.on('pageerror', e => e2.push(e.message)); T.rpc.length = 0;
    const st2 = mock(p2, { tasas: [{ fecha: hoy, tasa: 100 }], rest, sinMaquina: true, empresaExtra: { datos_confirmados: true } });
    await p2.goto('http://localhost:8765/farmacia.html'); await p2.fill('#lu', 'jose@azullab.com'); await p2.fill('#lp', 'clave-buena'); await p2.click('#loginForm [type=submit]');
    await p2.waitForFunction(() => (typeof S === 'object' && S.view !== 'login') && P.length === 1, null, { timeout: 8000 });
    await p2.evaluate(() => go('pos')); await p2.click('[data-act="add"][data-id="1"]'); await p2.click('[data-act="checkout"]'); await p2.click('[data-act="addpay"]');
    await p2.click('[data-act="emit"]'); await p2.waitForTimeout(300);
    ok((await p2.textContent('#toast')).includes('Falta configurar la impresora fiscal') && T.rpc.length === 0 && !st2.llamadas.some(l => l.p === '/rest/v1/rpc/vender'), 'sin impresora configurada no se factura (ni por imprenta ni por talonario)');
    await p2.evaluate(() => { closeModal(); go('fiscal'); });
    const tx = await p2.textContent('body');
    ok(tx.includes('Falta configurar la impresora fiscal') && await p2.$('[data-act="medio"]'), 'Módulo fiscal pide configurar la impresora');
    await p2.click('[data-act="medio"]'); await p2.waitForSelector('#mq-reg');
    ok(!(await p2.$('#mq-medio')), 'la configuración ya no ofrece imprenta digital');
    await p2.fill('#mq-reg', 'z7c0012345'); await p2.fill('#mq-ag', 'simulada'); await p2.click('[data-act="mq-cfg"]');
    await p2.waitForFunction(() => document.getElementById('toast').textContent.includes('ya puede facturar'));
    ok(st2.empresa.medio_factura === 'maquina' && st2.empresa.maquina_registro === 'Z7C0012345', 'al guardar la impresora queda como máquina fiscal');
    ok(e2.length === 0, 'sin errores de JavaScript ' + e2.join(' | ').slice(0, 300)); await c2.close(); }
  await b.close(); process.exit(fallas ? 1 : 0);
})();
