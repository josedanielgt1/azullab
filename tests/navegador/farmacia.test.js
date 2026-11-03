// Farmacia con datos reales: catálogo vacío → producto → compra → venta → salida (Supabase simulado en memoria)
const { chromium } = require('playwright'); const mock = require('./mock');
(async () => {
  const b = await chromium.launch(); let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
  const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Caracas' }).format(new Date());
  const T = { productos: [], lotes: [], clientes: [], docs: [], proveedores: [], compras: [], gastos: [], colecciones: [], movimientos: [], medicos: [], recipes: [], libro_controlados: [], alertas_pacientes: [], seq: 1, rpc: [] };
  const filtrar = (rows, u) => rows.filter(r => [...u.searchParams].every(([k, v]) => {
    if (['select', 'order', 'limit', 'offset', 'columns', 'on_conflict'].includes(k)) return true;
    const [op, ...rest] = v.split('.'); const val = rest.join('.');
    if (op === 'eq') return String(r[k]) === val; if (op === 'gt') return +r[k] > +val; if (op === 'gte') return String(r[k]) >= val;
    if (op === 'in') return val.slice(1, -1).split(',').includes(String(r[k])); return true; }));
  const rest = async (st, { m, p, u, b: body, q }) => {
    const uno = (q.headers()['accept'] || '').includes('vnd.pgrst.object');
    const out = x => ({ body: uno ? (Array.isArray(x) ? x[0] : x) : x });
    const tabla = { '/rest/v1/productos': 'productos', '/rest/v1/lotes': 'lotes', '/rest/v1/clientes': 'clientes', '/rest/v1/documentos': 'docs', '/rest/v1/proveedores': 'proveedores', '/rest/v1/compras': 'compras', '/rest/v1/gastos': 'gastos', '/rest/v1/movimientos': 'movimientos', '/rest/v1/medicos': 'medicos', '/rest/v1/recipes': 'recipes', '/rest/v1/libro_controlados': 'libro_controlados', '/rest/v1/alertas_pacientes': 'alertas_pacientes' }[p];
    if (p === '/rest/v1/colecciones' && m === 'GET') return out(T.colecciones);
    if (p === '/rest/v1/colecciones' && m === 'POST') { T.colecciones = T.colecciones.filter(c => c.nombre !== body.nombre).concat([body]); return out(body); }
    if (tabla && m === 'GET') return out(filtrar(tabla === 'docs' ? T[tabla].concat(T.otros || []) : T[tabla], u));
    if (tabla && m === 'POST') { const r = { activo: true, visitas: 0, total_usd: 0, puntos: 0, ...body, id: T.seq++ }; if (tabla === 'recipes') { r.numero = T.recipes.length + 1; r.fecha = new Date().toISOString(); }
      if (tabla === 'medicos' && T.medicos.some(x => x.nombre === r.nombre)) return out(r); if (tabla === 'clientes') r.cedula_rif = r.cedula_rif.toUpperCase();
      if (tabla === 'productos' && T.productos.some(x => x.codigo && x.codigo === r.codigo)) return { status: 409, body: { message: 'Uno de los códigos ya está en otro producto' } };
      T[tabla].push(r); return out(r); }
    if (tabla && m === 'PATCH') { const rs = filtrar(T[tabla], u); rs.forEach(r => Object.assign(r, body)); return out(rs); }
    if (p === '/rest/v1/perfiles') return out([{ user_id: 'u-d', nombre: 'José Guerrero' }]);
    if (p === '/rest/v1/rpc/tasa_del_dia') return { body: 100 };
    if (p === '/rest/v1/rpc/resumen_mensual') return { body: [{ mes: '2026-09-01', ventas_usd: 100, costo_usd: 60, gastos_usd: 10 }, { mes: '2026-10-01', ventas_usd: 200, costo_usd: 120, gastos_usd: 20 }, { mes: '2026-11-01', ventas_usd: 50, costo_usd: 30, gastos_usd: 5 }] };
    if (p.startsWith('/rest/v1/rpc/')) T.rpc.push({ f: p.slice(13), body });
    if (p === '/rest/v1/rpc/recibir_factura') { if (!T.proveedores.some(x => x.id === body.p_factura.proveedor_id)) return { status: 400, body: { message: 'Escoge la droguería' } };
      T.compras.push({ id: T.seq++, empresa_id: 'E', proveedor: 'Cobeca', numero: body.p_factura.numero, control: body.p_factura.control, fecha: body.p_factura.fecha, tipo: 'FAC', tasa: 100, exento_usd: 30, gravable_usd: 0, iva_usd: 0, total_usd: 30, pagado_usd: 0, vence: body.p_factura.fecha, rif: 'J-12345678-9' }); }
    if (p === '/rest/v1/rpc/recibir_factura' || p === '/rest/v1/rpc/recibir_compra') return { body: body.p_items.map(i => { let l = T.lotes.find(x => x.producto_id === i.producto_id && x.lote === i.lote.toUpperCase() && x.vence === i.vence);
      if (l) l.cantidad += i.cantidad; else { l = { id: T.seq++, empresa_id: 'E', producto_id: i.producto_id, lote: i.lote.toUpperCase(), vence: i.vence, cantidad: i.cantidad, costo: i.costo, precio: null }; T.lotes.push(l); } return l; }) };
    if (p === '/rest/v1/rpc/vender') {
      for (const it of body.p_items) { const disp = T.lotes.filter(l => l.producto_id === it.producto_id && l.vence >= hoy).reduce((t, l) => t + l.cantidad, 0);
        if (disp < it.cantidad) return { status: 400, body: { message: 'No hay existencia suficiente' } };
        let r = it.cantidad; T.lotes.filter(l => l.producto_id === it.producto_id && l.cantidad > 0 && l.vence >= hoy).sort((a, c) => a.vence.localeCompare(c.vence)).forEach(l => { const d = Math.min(l.cantidad, r); l.cantidad -= d; r -= d; }); }
      const n = T.docs.filter(d => d.tipo === 'FAC').length + 1, tot = body.p_items.reduce((t, i) => t + i.cantidad * i.precio_usd * 100, 0);
      const d = { id: 'doc-' + n, empresa_id: 'E', tipo: 'FAC', origen: 'sistema', numero: n, numero_control: null, fecha: new Date().toISOString(), cliente_rif: body.p_cliente.rif, cliente_nombre: body.p_cliente.nombre, tasa: 100, total: tot, total_usd: tot / 100, igtf: 0, ref_tipo: 'venta', creado_por: 'u-d',
        documento_lineas: body.p_items.map((i, k) => ({ renglon: k + 1, descripcion: 'x', cantidad: i.cantidad, precio_unit: i.precio_usd * 100, alicuota: 'E', ref: { producto_id: i.producto_id } })), documento_pagos: body.p_pagos.map(x => ({ metodo: x.metodo, monto_bs: x.monto_bs })) };
      T.docs.push(d); return { body: d }; }
    if (p === '/rest/v1/rpc/emitir_nota') {
      if (body.p_reintegrar) body.p_lineas.forEach(l => { const lt = T.lotes.find(x => x.producto_id === l.ref.producto_id && x.lote === 'GV24'); lt.cantidad += l.cantidad; });
      const n = T.docs.filter(d => d.tipo === body.p_tipo).length + 1, f = T.docs.find(d => d.id === body.p_factura);
      const d = { ...f, id: 'nota-' + n, tipo: body.p_tipo, numero: n, afecta_id: f.id, motivo: body.p_motivo, ref_tipo: null, documento_lineas: body.p_lineas.map((l, k) => ({ renglon: k + 1, descripcion: l.descripcion, cantidad: l.cantidad, precio_unit: l.precio_bs, alicuota: l.alicuota, ref: l.ref })), documento_pagos: [] };
      T.docs.push(d); return { body: d }; }
    if (p === '/rest/v1/rpc/salida_inventario') { const l = T.lotes.find(x => x.id === body.p_lote); if (body.p_cantidad > l.cantidad) return { status: 400, body: { message: 'La salida debe ser entre 1 y ' + l.cantidad } }; l.cantidad -= body.p_cantidad; return { body: l }; }
  };
  const ctx = await b.newContext(); const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message)); pg.on('console', m => { if (m.type() === 'error') console.log('   consola:', m.text().slice(0, 200)); });
  T.otros = [{ id: 'lab-1', empresa_id: 'L', tipo: 'FAC', numero: 1, total: 5000, igtf: 0, iva_general: 0, iva_reducida: 0, estado: 'emitido', fecha: new Date().toISOString(), tasa: 100, cliente_rif: 'V-1', cliente_nombre: 'X', documento_lineas: [], documento_pagos: [] }];
  mock(pg, { tasas: [{ fecha: hoy, tasa: 100 }], rest, empresas: [{ id: 'E', tipo: 'farmacia', razon_social: 'Azullab Farmacia, C.A.', rif: 'J-00000001-0' }, { id: 'L', tipo: 'laboratorio', razon_social: 'Grupo Empresarial Azullab, C.A.', rif: 'J-50134578-3' }] });
  await pg.goto('http://localhost:8765/farmacia.html'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]');
  await pg.waitForFunction(() => (typeof S === 'object' && S.view !== 'login'), null, { timeout: 8000 });
  ok(await pg.evaluate(() => P.length) === 0, 'instalación nueva: el catálogo arranca vacío');
  ok(await pg.evaluate(() => CLIENTS.length + S.sales.length + FX.docs.length + DROG.length + S.gastos.length + CUENTAS.length + COMPRAS_LIBRO.length + S.fallas.length + S.cots.length + S.movs.length + RX.length + CTRL.length + MEDICOS.length + Object.keys(ALERTAS).length) === 0, 'sin clientes, ventas, facturas, droguerías, gastos, cuentas, compras, fallas, récipes ni libro de controlados de muestra');
  ok(await pg.evaluate(() => EMP.length === 0 && DIF.length === 0), 'nómina y diferencial cambiario sin datos de muestra');
  ok(await pg.evaluate(() => FIN.mes.ventas === 50 && FIN.meses().length === 3 && finanzas().neta === 15), 'Ganancias y gastos usa las cifras de la base (50 − 30 − 5 = 15)');
  ok(await pg.evaluate(() => FX_SYS.excedente === 0 && typeof FX_SYS.islr === 'function'), 'sin excedente fiscal de muestra (la forma 30 no se reduce con datos inventados)');
  const gr = await pg.evaluate(() => FX_SYS.grupo(FX));
  ok(gr.length === 2 && gr[1].neg === 'Laboratorio' && gr[1].v === 5000 && gr[0].propio, 'el panel del grupo muestra las ventas reales del laboratorio (solo el dueño)');
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
  // Droguería y compra con su factura
  await pg.evaluate(() => go('suppliers')); await pg.fill('#drogname', 'Cobeca'); await pg.click('[data-act="drogadd"]');
  await pg.waitForFunction(() => DROG[0] && DROG[0]._id, null, { timeout: 5000 }).catch(() => {});
  await pg.fill('[data-drog="0"][data-f="rif"]', 'j123456789'); await pg.press('[data-drog="0"][data-f="rif"]', 'Tab'); await pg.waitForTimeout(500);
  ok(T.proveedores.length === 1 && T.proveedores[0].rif === 'J-12345678-9', 'la droguería se guarda con su RIF normalizado');
  await pg.evaluate(() => { RECV.push({ id: 1, l: 'gv25', e: '2028-03-31', q: 10, c: 2 }, { id: 1, l: 'GV24', e: '2027-01-31', q: 5, c: 2 }); go('purchases'); });
  await pg.click('[data-act="receive"]'); await pg.waitForTimeout(400);
  ok((await pg.textContent('#toast')).includes('número de la factura') && T.lotes.length === 0, 'sin número de factura no se recibe');
  await pg.fill('#fn', '0048213'); await pg.fill('#fc', '00-118204');
  await pg.click('[data-act="receive"]'); await pg.waitForFunction(() => P[0].stock === 15 && P[0].lots.every(l => l.id), null, { timeout: 10000 }).catch(() => {});
  ok(T.lotes.length === 2 && T.lotes.reduce((t, l) => t + l.cantidad, 0) === 15, 'la compra crea los lotes en la base');
  const rf = T.rpc.find(r => r.f === 'recibir_factura');
  ok(rf && rf.body.p_factura.numero === '0048213' && rf.body.p_factura.control === '00-118204' && rf.body.p_factura.proveedor_id === T.proveedores[0].id, 'con la factura del proveedor (número, control y droguería)');
  await pg.waitForFunction(() => COMPRAS_LIBRO.length === 1, null, { timeout: 5000 }).catch(() => {});
  ok(await pg.evaluate(() => COMPRAS_LIBRO.length === 1 && COMPRAS_LIBRO[0][2] === '0048213'), 'la factura aparece en el Libro de Compras');
  ok(await pg.evaluate(() => P[0].stock === 15 && P[0].lots.every(l => l.id)), 'la pantalla muestra 15 con los lotes de la base');
  // Venta
  await pg.evaluate(() => go('pos')); await pg.click('[data-act="add"][data-id="1"]'); await pg.click('[data-act="add"][data-id="1"]');
  ok(await pg.evaluate(() => { const c = getComputedStyle(document.getElementById('cartbox')); return c.maxHeight !== 'none' && c.overflowY === 'auto'; }), 'el panel de la venta se desplaza por dentro: el botón de cobrar siempre se alcanza');
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
  // Nota de crédito por devolución: 1 unidad vuelve al lote
  await pg.evaluate(() => { const d = FX.docs.find(x => x.tipo === 'FAC'); openModal(FX.ncModal(d)); });
  await pg.fill('[data-fxq="0"]', '1'); await pg.click('[data-act="fx-ncgo"]');
  await pg.waitForFunction(() => P[0].stock === 14 && FX.docs.some(d => d.tipo === 'NC'), null, { timeout: 6000 }).catch(() => {});
  const nc = T.rpc.find(r => r.f === 'emitir_nota');
  ok(nc && nc.body.p_tipo === 'NC' && nc.body.p_factura === 'doc-1' && nc.body.p_lineas[0].cantidad === 1 && nc.body.p_lineas[0].ref.producto_id === 1, 'la nota de crédito va a la base citando su factura');
  ok(nc && nc.body.p_reintegrar === /devoluci/i.test(nc.body.p_motivo), 'si es devolución, pide reintegrar al inventario');
  ok(await pg.evaluate(() => FX.docs.find(d => d.tipo === 'NC').num) === '00000001', 'la nota sale con el número que dio la base');
  ok(await pg.evaluate(() => P[0].stock) === 14, 'la pantalla toma la existencia de la base (14)');
  await pg.evaluate(() => closeModal());
  // Venta sin existencia: la base la rechaza
  await pg.evaluate(() => { S.cart = [{ id: 1, q: 50 }]; S.pays = [{ k: 'Pago móvil', div: false, a: 160 }]; openModal(payModal()); });
  await pg.click('[data-act="emit"]'); await pg.waitForTimeout(500);
  ok((await pg.textContent('#toast')).includes('No hay existencia'), 'sin existencia, la base no deja facturar');
  ok(T.docs.filter(d => d.tipo === 'FAC').length === 1, 'y no se emite factura');
  await pg.evaluate(() => { closeModal(); S.cart = []; S.pays = []; });
  // Salida
  await pg.evaluate(() => { go('inventory'); openModal(salidaModal({ id: 1 })); });
  await pg.selectOption('#sa-l', 'GV25'); await pg.fill('#sa-q', '2'); await pg.click('#salidaForm [type=submit]'); await pg.waitForTimeout(600);
  ok(T.rpc.some(r => r.f === 'salida_inventario' && r.body.p_cantidad === 2), 'la salida pasa por la base');
  ok(T.lotes.find(l => l.lote === 'GV25').cantidad === 8 && await pg.evaluate(() => P[0].stock) === 12, 'y descuenta el lote: queda 12');
  // Cuentas por pagar y gasto
  await pg.evaluate(() => go('suppliers')); await pg.click('[data-act="fr-pagar"]'); await pg.fill('#fr-m', '10'); await pg.click('#fr-pago [type=submit]'); await pg.waitForTimeout(400);
  ok(T.rpc.some(r => r.f === 'pagar_compra' && r.body.p_monto === 10), 'registrar pago a la droguería pasa por la base');
  await pg.evaluate(() => { S.gastos.push({ f: '01/11/2026', cat: 'Alquiler', desc: 'Local', cta: 'Banesco', usd: 650, fijo: true, ret: null }); render(); }); await pg.click('body'); await pg.waitForTimeout(500);
  ok(T.gastos.length === 1 && T.gastos[0].usd === 650 && T.gastos[0].datos.cat === 'Alquiler', 'el gasto se guarda en la base');
  await pg.evaluate(() => { S.gastos.splice(0, 1); render(); }); await pg.click('body'); await pg.waitForTimeout(500);
  ok(T.gastos[0].anulado === true, 'anular un gasto lo marca anulado (no se borra)');
  await pg.evaluate(() => { CFG.gan = 35; S.fallas.push({ p: 'Acetaminofén', u: 'José' }); }); await pg.click('body'); await pg.waitForTimeout(500);
  ok(T.colecciones.some(c => c.nombre === 'config' && c.datos.gan === 35) && T.colecciones.some(c => c.nombre === 'equipo_fallas'), 'la configuración y las fallas se guardan');
  // Récipe con médico nuevo y pestañas de récipes
  await pg.evaluate(() => { P[0].rx = true; go('recipes'); }); await pg.click('[data-act="rxnew"]'); await pg.selectOption('#rx-prod', 'Losartán 50 mg').catch(() => {});
  await pg.fill('#rx-ci', 'V-18.456.123'); await pg.fill('#rx-pac', 'María Rondón'); await pg.selectOption('#rx-med', 'new');
  await pg.fill('#rx-mn', 'Dr. Alfredo Molina'); await pg.fill('#rx-mm', '45.210'); await pg.fill('#rx-rec', '2'); await pg.fill('#rx-desp', '1');
  await pg.click('#rxForm [type=submit]'); await pg.waitForFunction(() => RX[0] && RX[0]._id, null, { timeout: 5000 }).catch(() => {});
  ok(T.medicos.length === 1 && T.medicos[0].mpps === '45.210', 'el médico nuevo se guarda con su MPPS');
  ok(T.recipes.length === 1 && T.recipes[0].paciente === 'María Rondón' && T.recipes[0].producto_id === 1 && T.recipes[0].recetado === 2, 'el récipe se guarda en la base con su producto');
  ok(await pg.evaluate(() => RX[0].id === 1), 'y toma el número que dio la base');
  for (const k of ['lista', 'paciente', 'libro']) { const n = errs.length; await pg.evaluate(x => { S.rxTab = x; render(); }, k).catch(e => errs.push(k + ': ' + e.message)); if (errs.length > n) console.log('   pestaña rota:', k, errs.slice(n).join(' | ').slice(0, 160)); }
  await pg.evaluate(() => { S.rxTab = 'paciente'; render(); }); await pg.fill('#rx-pci', 'V-18456123'); await pg.click('[data-act="rxpac"]');
  ok((await pg.textContent('#app')).includes('María Rondón') && (await pg.textContent('#app')).includes('1 de 2'), 'la ficha del paciente muestra sus récipes y lo pendiente');
  await pg.fill('#rx-alt', 'Alergia a la penicilina'); await pg.fill('#rx-alp', 'Amoxicilina, Penicilina'); await pg.click('[data-act="rxala"]'); await pg.waitForTimeout(500);
  ok(T.alertas_pacientes.length === 1 && T.alertas_pacientes[0].principios.length === 2, 'la regente registra una alerta del paciente');
  ok(await pg.evaluate(() => Object.values(ALERTAS).some(a => a.acts.includes('Amoxicilina'))), 'y la caja la tiene para frenar la venta');
  // Cliente nuevo
  await pg.evaluate(() => { CLIENTS.unshift({ ci: 'V-12.990.441', name: 'José Peña', tel: '—', visits: 0, total: 0, last: '—', pts: 0 }); render(); });
  await pg.click('body'); await pg.waitForTimeout(500);
  ok(T.clientes.length === 1 && T.clientes[0].cedula_rif === 'V-12990441', 'el cliente nuevo se guarda con la cédula normalizada');
  // Reportes y cierre con datos reales; ventas por cajero sin duplicar
  await pg.evaluate(() => go('reports')); const tr = await pg.textContent('#app');
  ok(!tr.includes('Dolor y fiebre') && !tr.includes('Punto de venta') && tr.includes('Efectivo Bs'), 'Reportes muestra solo las formas de pago y secciones reales (sin porcentajes de muestra)');
  ok(await pg.evaluate(() => byUser().reduce((t, r) => t + r.n, 0) === S.sales.length), 'ventas de hoy por cajero: cada factura una sola vez');
  await pg.fill('[data-cierre="Efectivo Bs"]', '600'); await pg.press('[data-cierre="Efectivo Bs"]', 'Tab'); await pg.waitForTimeout(200);
  ok((await pg.textContent('#app')).includes('Bs -40,00'), 'el cierre de caja calcula la diferencia con lo contado (640 − 600)');
  await pg.click('[data-act="fr-cierre"]'); await pg.waitForTimeout(500);
  ok(T.colecciones.some(c => c.nombre === 'equipo_cierres' && c.datos.length === 1), 'el cierre de caja queda guardado');
  // Cuentas y bancos, Azul Puntos y libro de ventas: sin cifras de muestra
  await pg.evaluate(() => go('banks')); const tb = await pg.textContent('#app');
  ok(tb.includes('Cobrado hoy') && !tb.includes('Unidad Educativa') && !tb.includes('Yorbelis'), 'Cuentas y bancos muestra lo cobrado hoy, sin deudores de muestra');
  ok(await pg.evaluate(() => LIBRO.length === FX.docs.length && LIBRO[0][1].startsWith('Factura')), 'el libro de ventas del módulo fiscal sale de las facturas');
  ok(await pg.evaluate(() => NAV.find(g => g.g === 'Operación').items.some(i => i[1] === 'recipes') && NAV.find(g => g.g === 'Administración').items.some(i => i[1] === 'suppliers')), 'Récipes y Proveedores quedan en el menú');
  ok(await pg.evaluate(() => !NAV.some(g => g.f2) && !NAV.some(g => g.items.some(i => ['loyalty', 'store', 'branches'].includes(i[1])))), 'la fase 2 no aparece en el menú');
  // Quincena de hoy y su pago guardado
  ok(await pg.evaluate(() => /quincena de/.test(QUIN.nombre) && !/octubre de 2026/.test(QUIN.nombre + 'x') && QUIN.id.length === 9), 'la quincena se calcula con la fecha de hoy');
  await pg.evaluate(() => { S.nomPagos = S.nomPagos || []; S.nomPagos.push({ periodo: QUIN.id, nombre: QUIN.nombre, fecha: new Date().toISOString(), total: 100, personas: [] }); }); await pg.click('body'); await pg.waitForTimeout(500);
  ok(T.colecciones.some(c => c.nombre === 'privado_nomina_pagos' && c.datos[0].periodo), 'el pago de la quincena queda guardado');
  // Recargar: todo sigue ahí
  await pg.reload(); await pg.waitForFunction(() => (typeof S === 'object' && S.view !== 'login') && P.length === 1 && FX.docs.length === 2, null, { timeout: 8000 }).catch(() => {});
  ok(await pg.evaluate(() => S.nomEstado === 'pagada' && P.length === 1 && P[0].stock === 12 && CLIENTS.length === 1 && FX.docs.length === 2 && FX.docs[1].afecta === FX.docs[0].id), 'al recargar siguen ahí producto, existencia, cliente, factura, su nota y la quincena pagada');
  ok(errs.length === 0, 'sin errores de JavaScript ' + errs.join(' | '));
  await b.close(); process.exit(fallas ? 1 : 0);
})();
