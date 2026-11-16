// Farmacia: el vuelto que no sale exacto. El cajero redondea a favor del cliente o deja parte en caja;
// lo marca, queda anotado en la factura y el cierre de caja lo muestra. Supabase simulado.
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
      const d = { id: 'doc-' + n, empresa_id: 'E', tipo: 'FAC', origen: 'sistema', numero: n, numero_control: null, medio: 'maquina', estado: 'pendiente_imprenta', fecha: new Date().toISOString(), cliente_rif: body.p_cliente.rif, cliente_nombre: body.p_cliente.nombre, tasa: 100, vuelto_ajuste: +(body.p_pagos.reduce((t, x) => t + (x.monto_bs || 0), 0) - tot).toFixed(2), vuelto_nota: (body.p_pagos.find(x => x.ajuste) || {}).nota || null, total: tot, total_usd: tot / 100, igtf: 0, base_exenta: tot, base_general: 0, iva_general: 0, base_reducida: 0, iva_reducida: 0, ref_tipo: 'venta', creado_por: 'u-d',
        documento_lineas: body.p_items.map((i, k) => ({ renglon: k + 1, descripcion: 'Losartán 50 mg', cantidad: i.cantidad, precio_unit: i.precio_usd * 100, alicuota: 'E', ref: { producto_id: i.producto_id } })),
        documento_pagos: body.p_pagos.filter(x => !x.ajuste).map((x, k) => ({ id: n * 10 + k, metodo: x.metodo, monto_bs: x.monto_bs, divisa: !!x.divisa, vuelto: x.monto_bs < 0 })) };
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

  // Producto de $3; 4 unidades = $12 = Bs 1.200 (tasa 100). Paga $50: el vuelto es $38 = Bs 3.800… para el ejemplo, paga Bs 4.956,56 → vuelto Bs 3.756,56
  const cobrar = async () => { await carrito(4); await pg.click('[data-act="addpay"][data-k="Efectivo Bs"]'); await pg.fill('#modal [data-pay="0"]', '4956,56'); await pg.press('#modal [data-pay="0"]', 'Tab'); await pg.click('#modal [data-act="vuelto"]'); };
  const est = () => pg.textContent('#vto-est'); const bloqueado = async () => await pg.locator('#vto-ok[disabled]').count() === 1;

  // ---- Redondeo a favor del cliente: vuelto Bs 3.756,56 y entrega Bs 3.800
  await cobrar();
  ok((await pg.textContent('#modal .vto-tot')).includes('3.756,56'), 'el vuelto del ejemplo: Bs 3.756,56');
  await pg.fill('#modal [data-vto="0"]', '3800');
  ok((await est()).includes('Entregas de más') && (await pg.textContent('#vto-est [data-vto-aj]')).includes('43,44') && await bloqueado(), 'al entregar Bs 3.800 avisa que son Bs 43,44 de más y no factura todavía');
  ok(await pg.locator('#modal #vto-nota').count() === 0, 'sin marcarlo no hay nota');
  await pg.click('#vto-est [data-act="vtoaj"]');
  ok((await est()).includes('Redondeo a favor del cliente') && (await pg.textContent('#vto-est [data-vto-aj]')).includes('43,44') && !(await bloqueado()), 'marcado como redondeo, ya se puede facturar');
  ok((await pg.inputValue('#modal [data-vto="0"]')) === '3.800,00', 'y lo entregado se conserva');
  await pg.fill('#modal [data-vto="0"]', '3900');
  ok(await pg.evaluate(() => S.vtoAj === false) && (await est()).includes('Te pasaste') && (await est()).includes('100,00') && await pg.locator('#vto-est [data-act="vtoaj"]').count() === 0 && await bloqueado(), 'pasarse de 1 dólar (Bs 100) no se puede marcar como redondeo');
  await pg.fill('#modal [data-vto="0"]', '3800'); await pg.click('#vto-est [data-act="vtoaj"]');
  await pg.click('#modal .row [data-act="vtoback"]');
  ok(/Vuelto: Efectivo Bs.*3\.800,00.*redondeo a favor del cliente.*43,44/.test(await modal()), 'el cobro resume: lo entregado y el redondeo');
  await pg.click('#modal [data-act="emit"]'); await pg.waitForFunction(() => document.getElementById('modal').textContent.includes('900000001'), null, { timeout: 8000 }).catch(() => {});
  let v = T.rpc[0] ? T.rpc[0].p_pagos : [];
  ok(v.length === 3 && v[0].monto_bs === 4956.56 && v[1].monto_bs === -3800 && v[2].ajuste === 'redondeo', 'a la base va lo que entró, los Bs 3.800 que salieron y la marca de redondeo');
  ok(/CAMBIO\s+Bs 3\.756,56/.test(await modal()), 'el ticket fiscal trae el cambio de la factura (Bs 3.756,56)');

  // ---- Entrega de menos: Bs 3.000 y el resto queda en caja (más de 1 dólar: pide la nota)
  await cobrar();
  ok(await pg.evaluate(() => S.vtoAj === false && S.vtoNota === ''), 'la venta siguiente arranca sin marcas');
  await pg.fill('#modal [data-vto="0"]', '3000');
  ok((await est()).includes('Falta por entregar') && (await pg.textContent('#vto-est [data-vto-aj]')).includes('756,56') && await bloqueado(), 'al entregar Bs 3.000 faltan Bs 756,56 y no factura');
  await pg.click('#vto-est [data-act="vtoaj"]');
  ok((await est()).includes('Queda en caja') && (await pg.textContent('#modal label[for="vto-nota"]')).includes('obligatorio') && await bloqueado(), '«Dejar en caja» pide el porqué cuando es más de 1 dólar');
  await pg.fill('#vto-nota', 'No había sencillo, pasa mañana');
  ok(!(await bloqueado()), 'con la nota escrita se puede facturar');
  await pg.click('#vto-ok'); await pg.waitForFunction(() => document.getElementById('modal').textContent.includes('900000002'), null, { timeout: 8000 }).catch(() => {});
  v = T.rpc[1] ? T.rpc[1].p_pagos : [];
  ok(v.length === 3 && v[1].monto_bs === -3000 && v[2].ajuste === 'en_caja' && v[2].nota === 'No había sencillo, pasa mañana', 'a la base van los Bs 3.000 que salieron, la marca «en caja» y la nota');

  // ---- Todo el vuelto queda en caja
  await cobrar();
  await pg.click('#vto-est [data-act="vtoaj"]'); await pg.fill('#vto-nota', 'El cliente lo dejó');
  ok((await pg.textContent('#vto-est [data-vto-aj]')).includes('3.756,56') && !(await bloqueado()), 'sin entregar nada, todo el vuelto (Bs 3.756,56) puede quedar en caja con su nota');
  await pg.click('#vto-ok'); await pg.waitForFunction(() => document.getElementById('modal').textContent.includes('900000003'), null, { timeout: 8000 }).catch(() => {});
  v = T.rpc[2] ? T.rpc[2].p_pagos : [];
  ok(v.length === 2 && v[0].monto_bs === 4956.56 && v[1].ajuste === 'en_caja', 'y a la base va solo el pago y la marca');

  // ---- Poca diferencia en caja: sin nota
  await cobrar(); await pg.fill('#modal [data-vto="0"]', '3750'); await pg.click('#vto-est [data-act="vtoaj"]');
  ok((await pg.textContent('#modal label[for="vto-nota"]')).includes('opcional') && !(await bloqueado()), 'dejar Bs 6,56 en caja no exige nota');
  await pg.click('#vto-ok'); await pg.waitForFunction(() => document.getElementById('modal').textContent.includes('900000004'), null, { timeout: 8000 }).catch(() => {});
  // ---- Vuelto exacto: sin marcas
  await cobrar(); await pg.click('#modal [data-act="vtotodo"][data-i="0"]');
  ok((await est()).includes('Vuelto completo') && await pg.locator('#modal #vto-nota').count() === 0 && !(await bloqueado()), 'con el vuelto exacto no hay nada que marcar');
  await pg.click('#vto-ok'); await pg.waitForFunction(() => document.getElementById('modal').textContent.includes('900000005'), null, { timeout: 8000 }).catch(() => {});
  ok(T.rpc[4] && T.rpc[4].p_pagos.length === 2 && !T.rpc[4].p_pagos.some(x => x.ajuste), 'y no viaja ninguna marca');

  // ---- Cierre de caja: da exacto y explica la diferencia
  const cierre = async () => { await pg.evaluate(() => { closeModal(); go('reports'); }); await pg.waitForFunction(() => document.body.textContent.includes('Cierre de caja'), null, { timeout: 5000 }).catch(() => {});
    return pg.evaluate(() => { const s = [...document.querySelectorAll('section.panel')].find(x => x.querySelector('h2') && x.querySelector('h2').textContent.trim().endsWith('Cierre de caja'));
      return { bs: [...s.querySelectorAll('tbody tr')].find(tr => tr.cells[0].textContent.trim() === 'Efectivo Bs').cells[1].textContent.trim(), aj: (s.querySelector('[data-vto-cierre]') || {}).textContent || '' }; }); };
  // Entró 5 × 4.956,56 = 24.782,80; salió 3.800 + 3.000 + 0 + 3.750 + 3.756,56 = 14.306,56 → 10.476,24
  // = facturado 6.000 + quedó en caja (756,56 + 3.756,56 + 6,56 = 4.519,68) − redondeo 43,44
  for (const paso of ['recién cobrado', 'leído de la base']) {
    if (paso === 'leído de la base') { await pg.reload(); await pg.waitForFunction(() => (typeof S === 'object' && S.view !== 'login') && P.length === 1 && FX.docs.length === 5, null, { timeout: 8000 }).catch(() => {}); }
    const c = await cierre();
    ok(c.bs === 'Bs 10.476,24', `cierre (${paso}): el efectivo en bolívares que debe haber es Bs 10.476,24`);
    ok(/Vuelto que quedó en caja\s*Bs 4\.519,68\s*·\s*3 ventas/.test(c.aj), `cierre (${paso}): vuelto que quedó en caja Bs 4.519,68 en 3 ventas`);
    ok(/Redondeos a favor del cliente\s*Bs 43,44\s*·\s*1 venta/.test(c.aj), `cierre (${paso}): redondeos a favor del cliente Bs 43,44 en 1 venta`);
    ok(c.aj.includes('No había sencillo, pasa mañana') && c.aj.includes('El cliente lo dejó'), `cierre (${paso}): cada ajuste sale con su nota`);
  }
  const fac = await pg.evaluate(() => [FX.ticketText(FX.docs.find(d => d.vaj < 0)), FX.ticketText(FX.docs.find(d => d.vnota === 'El cliente lo dejó'))]);
  ok(/REDONDEO DE VUELTO\s+Bs 43,44/.test(fac[0]), 'la factura guardada dice el redondeo');
  ok(/VUELTO EN CAJA\s+Bs 3\.756,56/.test(fac[1]) && fac[1].includes('NOTA: EL CLIENTE LO DEJO'.slice(0, 12)), 'y la otra, el vuelto que quedó en caja con su nota');

  ok(errs.length === 0, 'sin errores de JavaScript ' + errs.join(' | '));
  await b.close(); console.log(fallas ? `\n${fallas} FALLARON` : '\nTodas pasaron'); process.exit(fallas ? 1 : 0);
})();
