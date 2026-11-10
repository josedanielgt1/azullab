// Vencimientos: escribir el año en Compras, lo vencido fuera de venta en la caja y corregir el vencimiento de un lote
const { chromium } = require('playwright'); const mock = require('./mock');
(async () => {
  const b = await chromium.launch(); let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
  const base = process.env.CUADRE_URL || 'http://localhost:8765';
  const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Caracas' }).format(new Date());
  const prod = (id, nombre, extra) => ({ id, empresa_id: 'E', activo: true, codigo: '75910' + id, codigos_alt: [], nombre, principio_activo: 'X' + id, laboratorio: 'Lab', presentacion: 'Caja', seccion: 'Otros', iva: 'E', costo: 2, margen: 50, precio: 3, pmvp: null, por_lote: false, minimo: 1, rx: false, controlado: false, historial: [], ...extra });
  const lote = (id, producto_id, l, vence, cantidad) => ({ id, empresa_id: 'E', producto_id, lote: l, vence, cantidad, costo: 2, precio: null });
  const nuevo = async rol => {
    const T = { rpc: [], productos: [prod(1, 'Solo vencido'), prod(2, 'Mitad vencido'), prod(3, 'Vigente'), prod(4, 'Agotado')],
      lotes: [lote(11, 1, 'V1', '0002-01-31', 5), lote(21, 2, 'V2', '2020-01-31', 4), lote(22, 2, 'B2', '2031-01-31', 2), lote(31, 3, 'B3', '2031-01-31', 9)], proveedores: [{ id: 1, empresa_id: 'E', nombre: 'Cobeca', rif: 'J-12345678-9', dias_credito: 0, activo: true }] };
    const rest = async (st, { m, p, u, b: body }) => {
      if (p === '/rest/v1/productos' && m === 'GET') { const ids = (u.searchParams.get('id') || '').match(/\d+/g); return { body: ids ? T.productos.filter(x => ids.includes(String(x.id))) : T.productos }; }
      if (p === '/rest/v1/lotes' && m === 'GET') { const ids = (u.searchParams.get('producto_id') || '').match(/\d+/g); return { body: T.lotes.filter(x => x.cantidad > 0 && (!ids || ids.includes(String(x.producto_id)))) }; }
      if (p === '/rest/v1/proveedores' && m === 'GET') return { body: T.proveedores };
      if (p === '/rest/v1/perfiles') return { body: [{ user_id: 'u-d', nombre: 'José Guerrero' }] };
      if (p === '/rest/v1/rpc/tasa_del_dia') return { body: 100 };
      if (p.startsWith('/rest/v1/rpc/')) T.rpc.push({ f: p.slice(13), body });
      if (p === '/rest/v1/rpc/corregir_vencimiento') { const l = T.lotes.find(x => x.id === body.p_lote); l.vence = body.p_vence; return { body: l }; }
      if (p.startsWith('/rest/v1/rpc/')) return { body: [] };
      if (m === 'GET') return { body: [] };
    };
    const ctx = await b.newContext({ locale: 'en-US' }); const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message));
    mock(pg, { rol, tasas: [{ fecha: hoy, tasa: 100 }], rest });
    await pg.goto(base + '/farmacia.html'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]');
    await pg.waitForFunction(() => (typeof S === 'object' && S.view !== 'login' && P.length === 4), null, { timeout: 8000 });
    return { T, pg, errs, ctx };
  };
  const aviso = pg => pg.textContent('#toast');

  let { T, pg, errs, ctx } = await nuevo('dueno');
  // Compras: el año se escribe tecla por tecla, como lo hace una persona
  await pg.evaluate(() => go('purchases'));
  await pg.fill('#scan', 'Vigente'); await pg.press('#scan', 'Enter'); await pg.waitForSelector('[data-recv="0"][data-f="e"]');
  await pg.fill('[data-recv="0"][data-f="l"]', 'n1'); await pg.press('[data-recv="0"][data-f="l"]', 'Tab'); await pg.waitForTimeout(150);
  ok(await pg.evaluate(() => document.activeElement.dataset.f === 'e' && RECV[0].l === 'N1'), 'Compras: del lote se pasa al vencimiento con Tab, sin perder el cursor');
  await pg.keyboard.type('01312027', { delay: 60 }); await pg.waitForTimeout(200);
  ok(await pg.evaluate(() => RECV[0].e) === '2027-01-31', 'Compras: al escribir el vencimiento a mano, el año queda completo (2027, no 0002)');
  ok(await pg.evaluate(() => { const i = document.querySelector('[data-recv="0"][data-f="e"]'); return i.min >= '2026-01-01' && i.max === '2100-12-31' && !i.classList.contains('miss'); }), 'el calendario arranca en hoy, no en el año 0000');
  await pg.evaluate(() => { RECV[0].e = '0002-01-31'; }); await pg.fill('#fn', '0048213'); await pg.click('[data-act="receive"]');
  ok(/escribe el año completo/.test(await aviso(pg)), 'un año de un dígito no se deja cargar');
  await pg.evaluate(() => { RECV[0].e = '2020-01-31'; }); await pg.click('[data-act="receive"]');
  ok(/ya está vencido: no se recibe/.test(await aviso(pg)) && T.rpc.every(r => !/recibir/.test(r.f)), 'mercancía ya vencida no se recibe');

  // Caja
  await pg.evaluate(() => go('pos'));
  const tarjeta = id => pg.evaluate(i => { const x = document.querySelector(`[data-act="add"][data-id="${i}"]`); return { off: x.disabled, t: x.textContent.replace(/\s+/g, ' ') }; }, id);
  let c = await tarjeta(1);
  ok(c.off && c.t.includes('Vencido · fuera de venta') && c.t.includes('Existencia 0'), 'caja: un producto con todo vencido sale «fuera de venta» y no se puede seleccionar');
  await pg.click('[data-act="add"][data-id="1"]', { force: true }).catch(() => {});
  ok(await pg.evaluate(() => S.cart.length) === 0, 'y no entra al carrito');
  c = await tarjeta(2);
  ok(!c.off && c.t.includes('Existencia 2') && c.t.includes('4 vencidas'), 'con una parte vencida, muestra solo lo vigente y avisa cuántas están vencidas');
  await pg.click('[data-act="add"][data-id="2"]'); await pg.click('[data-act="add"][data-id="2"]'); await pg.click('[data-act="add"][data-id="2"]');
  ok(await pg.evaluate(() => S.cart[0].q) === 2 && /lo que queda está vencido/.test(await aviso(pg)), 'no deja pasar de lo vigente (2), aunque haya 6 en total');
  c = await tarjeta(4);
  ok(!c.off && c.t.includes('Agotado') && !c.t.includes('Vencido'), 'un agotado sigue saliendo como agotado (para anotar la falla)');
  c = await tarjeta(3);
  ok(!c.off && c.t.includes('Existencia 9') && !c.t.includes('vencid'), 'lo vigente sale normal');

  // Inventario: corregir el vencimiento
  await pg.evaluate(() => go('inventory'));
  await pg.click('[data-act="lote-venc"][data-lote="11"]');
  ok((await pg.textContent('#modal')).includes('Solo vencido') && await pg.inputValue('#lv-f') === '', 'inventario: «Corregir» abre la ficha del lote; una fecha mala no se propone');
  await pg.click('[data-act="lote-venc-ok"]');
  ok(/fecha completa/.test(await aviso(pg)), 'sin fecha no guarda');
  await pg.fill('#lv-f', '2027-01-31'); await pg.click('[data-act="lote-venc-ok"]');
  ok(/por qué se corrige/.test(await aviso(pg)), 'sin motivo no guarda');
  await pg.fill('#lv-m', 'Se escribió mal al recibir'); await pg.click('[data-act="lote-venc-ok"]');
  await pg.waitForFunction(() => P.find(x => x.id === 1).lots[0].e === '2027-01-31', null, { timeout: 6000 }).catch(() => {});
  const r = T.rpc.find(x => x.f === 'corregir_vencimiento');
  ok(r && JSON.stringify(r.body) === JSON.stringify({ p_lote: 11, p_vence: '2027-01-31', p_motivo: 'Se escribió mal al recibir' }), 'guardar llama a corregir_vencimiento() con el lote, la fecha y el motivo');
  ok(await pg.evaluate(() => P.find(x => x.id === 1).lots[0].e) === '2027-01-31', 'la pantalla toma la fecha de la base');
  await pg.evaluate(() => go('pos')); c = await tarjeta(1);
  ok(!c.off && c.t.includes('Existencia 5'), 'y el producto vuelve a estar a la venta');
  ok(errs.length === 0, 'sin errores de JavaScript' + (errs.length ? ': ' + errs.join(' | ').slice(0, 200) : ''));
  await ctx.close();

  ({ T, pg, errs, ctx } = await nuevo('almacen'));
  await pg.evaluate(() => go('inventory'));
  ok(await pg.evaluate(() => !!document.querySelector('[data-act="lote-venc"]')), 'almacén puede corregir vencimientos');
  await ctx.close();
  ({ T, pg, errs, ctx } = await nuevo('cajero'));
  await pg.evaluate(() => { try { go('inventory'); } catch (_) {} });
  ok(await pg.evaluate(() => !document.querySelector('[data-act="lote-venc"]')), 'el cajero no');
  await ctx.close();

  await b.close();
  console.log(fallas ? `\n${fallas} FALLARON` : '\nTodas pasaron'); process.exit(fallas ? 1 : 0);
})();
