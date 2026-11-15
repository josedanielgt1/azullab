// Farmacia: primero el vuelto, después el ticket. El vuelto se reparte por forma de entrega,
// va a la base como pagos negativos y se resta en el cierre de caja. Supabase simulado.
const { chromium } = require('playwright'); const mock = require('./mock');
(async () => {
  const b = await chromium.launch(); let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
  const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Caracas' }).format(new Date());
  const T = { rpc: [], impresas: [], docs: [] };
  const rest = async (st, { m, p, u, b: body, q }) => {
    const uno = (q.headers()['accept'] || '').includes('vnd.pgrst.object');
    if (p === '/rest/v1/productos' && m === 'GET') return { body: [{ id: 1, empresa_id: 'E', codigo: '111', codigos_alt: [], nombre: 'Losartán 50 mg', principio_activo: 'Losartán', iva: 'E', costo: 2, margen: 50, precio: 3, por_lote: false, minimo: 5, rx: false, controlado: false, historial: [] }] };
    if (p === '/rest/v1/lotes' && m === 'GET') return { body: [{ id: 9, empresa_id: 'E', producto_id: 1, lote: 'A1', vence: '2028-01-01', cantidad: 50, costo: 2, precio: null }] };
    if (p === '/rest/v1/documentos' && m === 'GET') { const id = (u.searchParams.get('id') || '').replace('eq.', ''); const rs = id ? T.docs.filter(d => d.id === id) : T.docs; return { body: uno ? rs[0] || null : rs }; }
    if (p === '/rest/v1/rpc/tasa_del_dia') return { body: 100 };
    if (p === '/rest/v1/rpc/vender_impresa') { T.impresas.push(body); return { body: { id: 'i-' + body.p_numero, medio: 'maquina', numero_fiscal: body.p_numero } }; }
    if (p === '/rest/v1/rpc/vender') { T.rpc.push(body); const n = T.docs.length + 1, tot = body.p_items.reduce((t, i) => t + i.cantidad * i.precio_usd * 100, 0);
      const d = { id: 'doc-' + n, empresa_id: 'E', tipo: 'FAC', origen: 'sistema', numero: n, numero_control: null, medio: 'maquina', estado: 'pendiente_imprenta', fecha: new Date().toISOString(), cliente_rif: body.p_cliente.rif, cliente_nombre: body.p_cliente.nombre, tasa: 100, total: tot, total_usd: tot / 100, igtf: 0, base_exenta: tot, base_general: 0, iva_general: 0, base_reducida: 0, iva_reducida: 0, ref_tipo: 'venta', creado_por: 'u-d',
        documento_lineas: body.p_items.map((i, k) => ({ renglon: k + 1, descripcion: 'Losartán 50 mg', cantidad: i.cantidad, precio_unit: i.precio_usd * 100, alicuota: 'E', ref: { producto_id: i.producto_id } })),
        documento_pagos: body.p_pagos.map((x, k) => ({ id: n * 10 + k, metodo: x.metodo, monto_bs: x.monto_bs, divisa: !!x.divisa, vuelto: x.monto_bs < 0 })) };
      T.docs.push(d); return { body: d }; }
    if (p === '/rest/v1/rpc/registrar_maquina') { const d = T.docs.find(x => x.id === body.p_doc); Object.assign(d, { numero_fiscal: body.p_numero, maquina_registro: body.p_registro, estado: 'emitido' }); return { body: d }; }
    if (p === '/rest/v1/perfiles') return { body: [{ user_id: 'u-d', nombre: 'José Guerrero' }] };
    if (m === 'GET' && p.startsWith('/rest/v1/') && !p.includes('rpc')) return { body: uno ? null : [] };
  };
  const ctx = await b.newContext(); const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message));
  mock(pg, { tasas: [{ fecha: hoy, tasa: 100 }], rest, empresaExtra: { datos_confirmados: true } });
  await pg.goto('http://localhost:8765/farmacia.html'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]');
  await pg.waitForFunction(() => (typeof S === 'object' && S.view !== 'login') && P.length === 1, null, { timeout: 8000 });
  const modal = () => pg.textContent('#modal');
  const carrito = async n => { await pg.evaluate(() => { closeModal(); go('pos'); }); for (let i = 0; i < n; i++) await pg.click('[data-act="add"][data-id="1"]'); await pg.click('[data-act="checkout"]'); };

  // ---- Pago exacto: no hay paso de vuelto
  await carrito(1); await pg.click('[data-act="addpay"][data-k="Pago móvil"]');
  ok(await pg.locator('#modal [data-act="emit"]:not([disabled])').count() === 1 && await pg.locator('#modal [data-act="vuelto"]').count() === 0, 'con el pago exacto se emite directo, sin paso de vuelto');
  await pg.click('#modal [data-act="emit"]'); await pg.waitForFunction(() => document.getElementById('modal').textContent.includes('900000001'), null, { timeout: 8000 }).catch(() => {});
  ok(T.rpc.length === 1 && T.rpc[0].p_pagos.length === 1 && T.rpc[0].p_pagos[0].monto_bs === 300, 'y a la base va solo el pago');
  ok(!(await modal()).includes('CAMBIO'), 'el ticket no habla de cambio');

  // ---- El cliente paga $20 por $12
  await carrito(4); await pg.click('[data-act="addpay"][data-k="Efectivo USD"]');
  await pg.fill('#modal [data-pay="0"]', '20');
  ok(await pg.locator('#modal [data-act="vuelto"]').count() === 1 && await pg.locator('#modal [data-act="emit"]').count() === 0, 'al escribir un monto mayor, el botón de emitir cambia a «Entregar vuelto» sin esperar');
  await pg.press('#modal [data-pay="0"]', 'Tab');
  ok(/Vuelto por entregar/.test(await modal()) && (await pg.textContent('#modal [data-vto-pend]')).includes('800,00'), 'el cobro avisa el vuelto por entregar: Bs 800,00');
  ok((await pg.textContent('#modal [data-act="vuelto"]')).includes('Entregar vuelto'), 'y no deja emitir la factura todavía');
  // Aunque alguien dispare «emitir», la venta no sale sin repartir el vuelto
  await pg.evaluate(() => { const x = document.createElement('button'); x.dataset.act = 'emit'; x.id = 'forzado'; document.querySelector('#modal .bd').appendChild(x); x.click(); });
  await pg.waitForTimeout(400);
  ok(T.rpc.length === 1 && (await modal()).includes('Vuelto del cliente'), 'forzar la emisión abre el vuelto y no factura');
  await pg.click('#modal [data-act="vtoback"]'); await pg.click('#modal [data-act="vuelto"]');
  ok(/Vuelto del cliente\s*Bs 800,00\s*\$\s?8,00/.test(await pg.textContent('#modal .vto-tot')), 'la ventana del vuelto muestra el total en bolívares y dólares');
  ok(await pg.locator('#vto-ok[disabled]').count() === 1, 'no se puede facturar con el vuelto sin repartir');
  ok(await pg.locator('#modal [data-vto]').count() === 3, 'se entrega en efectivo Bs, efectivo USD o pago móvil');
  await pg.fill('#modal [data-vto="0"]', '500');
  ok((await pg.textContent('#vto-est')).includes('Falta por entregar') && (await pg.textContent('#vto-est')).includes('300,00') && await pg.locator('#vto-ok[disabled]').count() === 1, 'con Bs 500 en efectivo falta repartir Bs 300 y sigue sin facturar');
  await pg.fill('#modal [data-vto="0"]', '950');
  ok((await pg.textContent('#vto-est')).includes('Te pasaste') && await pg.locator('#vto-ok[disabled]').count() === 1, 'si se pasa del vuelto por más de 1 dólar tampoco factura');
  await pg.fill('#modal [data-vto="0"]', '500');
  await pg.click('#modal [data-act="vtotodo"][data-i="2"]');
  ok((await pg.textContent('#vto-est')).includes('Vuelto completo') && await pg.locator('#vto-ok:not([disabled])').count() === 1, '«Todo» en pago móvil pone lo que falta y el vuelto queda completo');
  ok(await pg.inputValue('#modal [data-vto="2"]') === '300,00', 'pago móvil quedó con Bs 300,00');
  // Volver al cobro conserva el vuelto; cambiar el pago lo borra
  await pg.click('#modal .row [data-act="vtoback"]');
  ok(/Vuelto: Efectivo Bs.*500,00.*Pago móvil.*300,00/.test(await modal()) && await pg.locator('#modal [data-act="emit"]:not([disabled])').count() === 1, 'al volver al cobro el vuelto ya repartido se ve y se puede emitir');
  await pg.fill('#modal [data-pay="0"]', '15'); await pg.press('#modal [data-pay="0"]', 'Tab');
  ok(await pg.evaluate(() => S.vuelto.length === 0) && (await pg.textContent('#modal [data-vto-pend]')).includes('300,00'), 'si cambia lo que pagó el cliente, el vuelto se reparte de nuevo (ahora Bs 300)');
  await pg.fill('#modal [data-pay="0"]', '20'); await pg.press('#modal [data-pay="0"]', 'Tab');
  await pg.click('#modal [data-act="vuelto"]'); await pg.fill('#modal [data-vto="0"]', '500'); await pg.click('#modal [data-act="vtotodo"][data-i="2"]');
  await pg.click('#vto-ok'); await pg.waitForFunction(() => document.getElementById('modal').textContent.includes('900000002'), null, { timeout: 8000 }).catch(() => {});
  const v = T.rpc[1], pg2 = v ? v.p_pagos : [];
  ok(v && pg2.length === 3 && pg2[0].metodo === 'Efectivo USD' && pg2[0].monto_bs === 2000 && pg2[0].divisa === true, 'a la base va lo que entregó el cliente: Efectivo USD Bs 2.000');
  ok(v && pg2[1].metodo === 'Efectivo Bs' && pg2[1].monto_bs === -500 && pg2[2].metodo === 'Pago móvil' && pg2[2].monto_bs === -300, 'y el vuelto como pagos negativos: Efectivo Bs −500 y Pago móvil −300');
  ok(v && Math.abs(pg2.reduce((t, x) => t + x.monto_bs, 0) - 1200) < 0.01, 'lo cobrado menos el vuelto da el total de la factura');
  const tk = await modal();
  ok(tk.includes('900000002') && /CAMBIO\s+Bs 800,00/.test(tk), 'el ticket sale después del vuelto y trae el cambio');
  ok(await pg.evaluate(() => S.vuelto.length === 0 && S.pays.length === 0), 'la venta siguiente arranca sin vuelto');
  await pg.waitForFunction(() => FX.docs.length === 2, null, { timeout: 6000 }).catch(() => {});
  ok(await pg.evaluate(() => S.sales[0].m === 'Efectivo USD'), 'en Mi turno la venta figura como Efectivo USD (el vuelto no la vuelve «Mixto»)');

  // ---- Cierre de caja: el vuelto se resta por forma de pago
  await pg.evaluate(() => { closeModal(); go('reports'); }); await pg.waitForFunction(() => document.body.textContent.includes('Cierre de caja'), null, { timeout: 5000 }).catch(() => {});
  const filas = await pg.evaluate(() => { const s = [...document.querySelectorAll('section.panel')].find(x => x.querySelector('h2') && x.querySelector('h2').textContent.trim().endsWith('Cierre de caja'));
    return Object.fromEntries([...s.querySelectorAll('tbody tr')].map(tr => [tr.cells[0].textContent.trim(), tr.cells[1].textContent.trim()])); });
  ok(filas['Efectivo USD'] === '$ 20,00', 'cierre: en dólares el sistema espera los $20 que entraron');
  ok(/^Bs -500,00$/.test(filas['Efectivo Bs'] || ''), 'cierre: los Bs 500 del vuelto salen del efectivo en bolívares');
  ok(/^Bs 0,00$/.test(filas['Pago móvil'] || ''), 'cierre: pago móvil queda en 0 (Bs 300 que entraron menos Bs 300 de vuelto)');
  const fac = await pg.evaluate(() => FX.ticketText(FX.docs.find(d => d.pagos.some(p => p.v))));
  ok(/VUELTO EFECTIVO BS\s+Bs 500,00/.test(fac) && !fac.includes('-500'), 'la factura guardada muestra el vuelto con su forma de entrega');

  // Otro día u otro equipo: las facturas vienen de la base (todo en bolívares) y el cierre da lo mismo
  await pg.reload(); await pg.waitForFunction(() => (typeof S === 'object' && S.view !== 'login') && P.length === 1 && FX.docs.length === 2, null, { timeout: 8000 }).catch(() => {});
  await pg.evaluate(() => go('reports')); await pg.waitForFunction(() => document.body.textContent.includes('Cierre de caja'), null, { timeout: 5000 }).catch(() => {});
  const filas2 = await pg.evaluate(() => { const s = [...document.querySelectorAll('section.panel')].find(x => x.querySelector('h2') && x.querySelector('h2').textContent.trim().endsWith('Cierre de caja'));
    return Object.fromEntries([...s.querySelectorAll('tbody tr')].map(tr => [tr.cells[0].textContent.trim(), tr.cells[1].textContent.trim()])); });
  ok(filas2['Efectivo USD'] === '$ 20,00' && filas2['Efectivo Bs'] === 'Bs -500,00' && filas2['Pago móvil'] === 'Bs 0,00', 'al recargar, el cierre sale igual con las facturas leídas de la base');
  ok(await pg.evaluate(() => S.sales.every(x => x.m !== 'Mixto')), 'y las ventas siguen con su forma de pago');

  // ---- Sin internet: el vuelto también va en la venta que queda en la cola
  await ctx.setOffline(true); await pg.waitForTimeout(300);
  await carrito(1); await pg.click('[data-act="addpay"][data-k="Efectivo Bs"]');
  await pg.fill('#modal [data-pay="0"]', '500'); await pg.press('#modal [data-pay="0"]', 'Tab');
  await pg.click('#modal [data-act="vuelto"]'); await pg.click('#modal [data-act="vtotodo"][data-i="0"]'); await pg.click('#vto-ok');
  await pg.waitForFunction(() => JSON.parse(localStorage.getItem('cuadre.farmacia.cola') || '[]').length === 1, null, { timeout: 8000 }).catch(() => {});
  const cola = await pg.evaluate(() => JSON.parse(localStorage.getItem('cuadre.farmacia.cola') || '[]'));
  ok(cola.length === 1 && cola[0].pagos.length === 2 && cola[0].pagos[0].monto_bs === 500 && cola[0].pagos[1].metodo === 'Efectivo Bs' && cola[0].pagos[1].monto_bs === -200, 'sin internet la venta queda en la cola con su vuelto (Bs 500 − Bs 200)');
  await ctx.setOffline(false); await pg.waitForFunction(() => !JSON.parse(localStorage.getItem('cuadre.farmacia.cola') || '[]').length, null, { timeout: 8000 }).catch(() => {});
  ok(T.impresas.length === 1 && T.impresas[0].p_pagos[1].monto_bs === -200, 'y al volver la conexión sube con el vuelto');

  ok(errs.length === 0, 'sin errores de JavaScript ' + errs.join(' | '));
  await b.close(); console.log(fallas ? `\n${fallas} FALLARON` : '\nTodas pasaron'); process.exit(fallas ? 1 : 0);
})();
