// Farmacia con datos reales: catálogo vacío → producto → compra → venta → salida (Supabase simulado en memoria)
const { chromium } = require('playwright'); const mock = require('./mock');
(async () => {
  const b = await chromium.launch(); let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
  const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Caracas' }).format(new Date());
  const T = { productos: [], lotes: [], clientes: [], docs: [], seq: 1, rpc: [] };
  const filtrar = (rows, u) => rows.filter(r => [...u.searchParams].every(([k, v]) => {
    if (['select', 'order', 'limit', 'offset', 'columns', 'on_conflict'].includes(k)) return true;
    const [op, ...rest] = v.split('.'); const val = rest.join('.');
    if (op === 'eq') return String(r[k]) === val; if (op === 'gt') return +r[k] > +val; if (op === 'gte') return String(r[k]) >= val;
    if (op === 'in') return val.slice(1, -1).split(',').includes(String(r[k])); return true; }));
  const rest = async (st, { m, p, u, b: body, q }) => {
    const uno = (q.headers()['accept'] || '').includes('vnd.pgrst.object');
    const out = x => ({ body: uno ? (Array.isArray(x) ? x[0] : x) : x });
    const tabla = { '/rest/v1/productos': 'productos', '/rest/v1/lotes': 'lotes', '/rest/v1/clientes': 'clientes', '/rest/v1/documentos': 'docs' }[p];
    if (tabla && m === 'GET') return out(filtrar(T[tabla], u));
    if (tabla && m === 'POST') { const r = { activo: true, visitas: 0, total_usd: 0, puntos: 0, ...body, id: T.seq++ }; if (tabla === 'clientes') r.cedula_rif = r.cedula_rif.toUpperCase();
      if (tabla === 'productos' && T.productos.some(x => x.codigo && x.codigo === r.codigo)) return { status: 409, body: { message: 'Uno de los códigos ya está en otro producto' } };
      T[tabla].push(r); return out(r); }
    if (tabla && m === 'PATCH') { const rs = filtrar(T[tabla], u); rs.forEach(r => Object.assign(r, body)); return out(rs); }
    if (p === '/rest/v1/perfiles') return out([{ user_id: 'u-d', nombre: 'José Guerrero' }]);
    if (p === '/rest/v1/rpc/tasa_del_dia') return { body: 100 };
    if (p.startsWith('/rest/v1/rpc/')) T.rpc.push({ f: p.slice(13), body });
    if (p === '/rest/v1/rpc/recibir_compra') return { body: body.p_items.map(i => { let l = T.lotes.find(x => x.producto_id === i.producto_id && x.lote === i.lote.toUpperCase() && x.vence === i.vence);
      if (l) l.cantidad += i.cantidad; else { l = { id: T.seq++, empresa_id: 'E', producto_id: i.producto_id, lote: i.lote.toUpperCase(), vence: i.vence, cantidad: i.cantidad, costo: i.costo, precio: null }; T.lotes.push(l); } return l; }) };
    if (p === '/rest/v1/rpc/vender') {
      for (const it of body.p_items) { const disp = T.lotes.filter(l => l.producto_id === it.producto_id && l.vence >= hoy).reduce((t, l) => t + l.cantidad, 0);
        if (disp < it.cantidad) return { status: 400, body: { message: 'No hay existencia suficiente' } };
        let r = it.cantidad; T.lotes.filter(l => l.producto_id === it.producto_id && l.cantidad > 0 && l.vence >= hoy).sort((a, c) => a.vence.localeCompare(c.vence)).forEach(l => { const d = Math.min(l.cantidad, r); l.cantidad -= d; r -= d; }); }
      const n = T.docs.filter(d => d.tipo === 'FAC').length + 1, tot = body.p_items.reduce((t, i) => t + i.cantidad * i.precio_usd * 100, 0);
      const d = { id: 'doc-' + n, empresa_id: 'E', tipo: 'FAC', origen: 'sistema', numero: n, numero_control: null, fecha: new Date().toISOString(), cliente_rif: body.p_cliente.rif, cliente_nombre: body.p_cliente.nombre, tasa: 100, total: tot, total_usd: tot / 100, igtf: 0, ref_tipo: 'venta', creado_por: 'u-d',
        documento_lineas: body.p_items.map((i, k) => ({ renglon: k + 1, descripcion: 'x', cantidad: i.cantidad, precio_unit: i.precio_usd * 100, alicuota: 'E', ref: { producto_id: i.producto_id } })), documento_pagos: body.p_pagos.map(x => ({ metodo: x.metodo, monto_bs: x.monto_bs })) };
      T.docs.push(d); return { body: d }; }
    if (p === '/rest/v1/rpc/salida_inventario') { const l = T.lotes.find(x => x.id === body.p_lote); if (body.p_cantidad > l.cantidad) return { status: 400, body: { message: 'La salida debe ser entre 1 y ' + l.cantidad } }; l.cantidad -= body.p_cantidad; return { body: l }; }
  };
  const ctx = await b.newContext(); const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message));
  mock(pg, { tasas: [{ fecha: hoy, tasa: 100 }], rest });
  await pg.goto('http://localhost:8765/farmacia.html'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]');
  await pg.waitForFunction(() => !document.getElementById('loginForm'), null, { timeout: 8000 });
  ok(await pg.evaluate(() => P.length) === 0, 'instalación nueva: el catálogo arranca vacío');
  ok(await pg.evaluate(() => CLIENTS.length + S.sales.length + FX.docs.length) === 0, 'sin clientes, ventas ni facturas de muestra');
  const vistas = await pg.evaluate(() => NAV.flatMap(g => g.items.map(i => i[1])));
  for (const v of vistas) { const n = errs.length; await pg.evaluate(x => go(x), v).catch(e => errs.push(v + ': ' + e.message)); if (errs.length > n) console.log('   rota con catálogo vacío:', v, errs.slice(n).join(' | ').slice(0, 160)); }
  ok(errs.length === 0, `las ${vistas.length} pantallas abren con todo vacío`);
  // Producto nuevo
  await pg.evaluate(() => go('products')); await pg.click('[data-act="prodnew"]');
  await pg.fill('#p-name', 'Losartán 50 mg'); await pg.fill('#p-act', 'Losartán'); await pg.fill('#p-code', '7591020311042'); await pg.fill('#p-cost', '2'); await pg.fill('#p-marg', '50');
  await pg.click('#prodForm [type=submit]'); await pg.waitForFunction(() => P[0] && P[0].id === 1, null, { timeout: 5000 }).catch(() => {});
  ok(T.productos.length === 1 && T.productos[0].nombre === 'Losartán 50 mg' && T.productos[0].precio === 3, 'el producto nuevo se guarda en la base con su precio (costo 2 + 50 % = 3)');
  ok(await pg.evaluate(() => P[0].id) === 1, 'y toma el número que le dio la base');
  await pg.click('[data-act="prodnew"]'); await pg.fill('#p-name', 'Otro'); await pg.fill('#p-act', '-'); await pg.fill('#p-code', '7591020311042'); await pg.fill('#p-cost', '1'); await pg.fill('#p-marg', '30');
  await pg.click('#prodForm [type=submit]'); await pg.waitForTimeout(400);
  ok(T.productos.length === 1, 'un código repetido no entra');
  await pg.evaluate(() => closeModal());
  // Editar el precio (margen)
  await pg.evaluate(() => { S.altTmp = []; openModal(prodModal(P[0])); });
  await pg.fill('#p-marg', '60'); await pg.click('#prodForm [type=submit]'); await pg.waitForTimeout(500);
  ok(T.productos[0].precio === 3.2 && T.productos[0].margen === 60, 'editar la ganancia actualiza el precio en la base (3,20)');
  // Compra
  await pg.evaluate(() => { RECV.push({ id: 1, l: 'gv25', e: '2028-03-31', q: 10, c: 2 }, { id: 1, l: 'GV24', e: '2027-01-31', q: 5, c: 2 }); go('purchases'); });
  await pg.click('[data-act="receive"]'); await pg.waitForFunction(() => P[0].stock === 15, null, { timeout: 5000 }).catch(() => {});
  ok(T.lotes.length === 2 && T.lotes.reduce((t, l) => t + l.cantidad, 0) === 15, 'la compra crea los lotes en la base');
  ok(await pg.evaluate(() => P[0].stock === 15 && P[0].lots.every(l => l.id)), 'la pantalla muestra 15 con los lotes de la base');
  // Venta
  await pg.evaluate(() => go('pos')); await pg.click('[data-act="add"][data-id="1"]'); await pg.click('[data-act="add"][data-id="1"]');
  await pg.click('[data-act="checkout"]'); await pg.click('[data-act="addpay"]');
  await pg.click('[data-act="emit"]'); await pg.waitForFunction(() => document.body.textContent.includes('00000001'), null, { timeout: 5000 }).catch(() => {});
  await pg.waitForFunction(() => document.getElementById('modal').textContent.includes('00000001') && P[0].stock === 13, null, { timeout: 8000 }).catch(() => {});
  const v = T.rpc.find(r => r.f === 'vender');
  ok(v && v.body.p_items[0].cantidad === 2 && v.body.p_items[0].precio_usd === 3.2, 'cobrar llama a vender() con cantidad y precio');
  ok(v && v.body.p_pagos[0].monto_bs === 640, 'con el pago en bolívares a la tasa de la base');
  ok((await pg.textContent('#modal')).includes('00000001'), 'el ticket sale con el número que dio la base');
  ok(T.lotes.find(l => l.lote === 'GV24').cantidad === 3, 'en la base sale primero el lote que vence antes');
  ok(await pg.evaluate(() => P[0].stock) === 13, 'la pantalla queda en 13');
  ok(await pg.evaluate(() => S.sales.length === 1 && FX.docs.length === 1), 'la venta aparece en Mi turno y en Facturas');
  await pg.evaluate(() => closeModal());
  // Venta sin existencia: la base la rechaza
  await pg.evaluate(() => { S.cart = [{ id: 1, q: 50 }]; S.pays = [{ k: 'Pago móvil', div: false, a: 160 }]; openModal(payModal()); });
  await pg.click('[data-act="emit"]'); await pg.waitForTimeout(500);
  ok((await pg.textContent('#toast')).includes('No hay existencia'), 'sin existencia, la base no deja facturar');
  ok(T.docs.length === 1, 'y no se emite factura');
  await pg.evaluate(() => { closeModal(); S.cart = []; S.pays = []; });
  // Salida
  await pg.evaluate(() => { go('inventory'); openModal(salidaModal({ id: 1 })); });
  await pg.selectOption('#sa-l', 'GV25'); await pg.fill('#sa-q', '2'); await pg.click('#salidaForm [type=submit]'); await pg.waitForTimeout(600);
  ok(T.rpc.some(r => r.f === 'salida_inventario' && r.body.p_cantidad === 2), 'la salida pasa por la base');
  ok(T.lotes.find(l => l.lote === 'GV25').cantidad === 8 && await pg.evaluate(() => P[0].stock) === 11, 'y descuenta el lote: queda 11');
  // Cliente nuevo
  await pg.evaluate(() => { CLIENTS.unshift({ ci: 'V-12.990.441', name: 'José Peña', tel: '—', visits: 0, total: 0, last: '—', pts: 0 }); render(); });
  await pg.click('body'); await pg.waitForTimeout(500);
  ok(T.clientes.length === 1 && T.clientes[0].cedula_rif === 'V-12990441', 'el cliente nuevo se guarda con la cédula normalizada');
  // Recargar: todo sigue ahí
  await pg.reload(); await pg.waitForFunction(() => !document.getElementById('loginForm') && P.length === 1 && FX.docs.length === 1, null, { timeout: 8000 }).catch(() => {});
  ok(await pg.evaluate(() => P.length === 1 && P[0].stock === 11 && CLIENTS.length === 1 && FX.docs.length === 1), 'al recargar, producto, existencia, cliente y factura siguen ahí');
  ok(errs.length === 0, 'sin errores de JavaScript ' + errs.join(' | '));
  await b.close(); process.exit(fallas ? 1 : 0);
})();
