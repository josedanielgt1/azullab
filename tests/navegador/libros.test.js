// Libros: registro de inventario real (art. 177), nota de descuento sin tocar existencia,
// libro de ventas por Reporte Z (máquina fiscal) y nota de crédito de droguería. Supabase simulado.
const { chromium } = require('playwright'); const mock = require('./mock');
(async () => {
  const b = await chromium.launch(); let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
  const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Caracas' }).format(new Date());
  const T = { productos: [{ id: 1, empresa_id: 'E', codigo: '759', codigos_alt: [], nombre: 'Losartán 50 mg', principio_activo: 'Losartán', laboratorio: '—', presentacion: 'Caja x 30', seccion: 'Otros', iva: 'E', costo: 2, margen: 50, precio: 3, pmvp: null, por_lote: false, minimo: 5, rx: false, controlado: false, historial: [], activo: true }],
    lotes: [{ id: 10, empresa_id: 'E', producto_id: 1, lote: 'A1', vence: '2030-01-01', cantidad: 24, costo: 2, precio: null }],
    compras: [{ id: 50, empresa_id: 'E', proveedor_id: 7, proveedor: 'Cobeca', rif: 'J-12345678-9', tipo: 'FAC', numero: '0048213', control: '00-1', fecha: hoy, tasa: 100, exento_usd: 40, gravable_usd: 0, iva_usd: 0, total_usd: 40, vence: hoy, pagado_usd: 0, afecta_id: null }],
    docs: [], rpc: [], seq: 100 };
  const z = (n, num, extra) => ({ id: 'd' + num, empresa_id: 'E', tipo: 'FAC', origen: 'sistema', numero: n, numero_control: null, estado: 'emitido', medio: 'maquina', maquina_registro: 'Z7C0012345', numero_fiscal: num, reporte_z: 87,
    fecha: new Date().toISOString(), cliente_rif: 'V-00000000', cliente_nombre: 'Consumidor final', tasa: 100, base_exenta: 300, base_general: 0, iva_general: 0, base_reducida: 0, iva_reducida: 0, igtf: 0, total: 300, total_usd: 3,
    ref_tipo: 'venta', creado_por: 'u-d', afecta_id: null, documento_lineas: [{ renglon: 1, descripcion: 'Losartán', cantidad: 1, precio_unit: 300, alicuota: 'E', ref: { producto_id: 1 } }], documento_pagos: [{ metodo: 'Pago móvil', monto_bs: 300 }], ...extra });
  T.docs.push(z(1, 1501), z(2, 1502), z(3, 1503, { cliente_rif: 'J-41203398-5', cliente_nombre: 'Unidad Educativa' }), z(4, 1504, { reporte_z: null }));
  const filtrar = (rows, u) => rows.filter(r => [...u.searchParams].every(([k, v]) => {
    if (['select', 'order', 'limit', 'offset', 'columns', 'on_conflict'].includes(k)) return true;
    const [op, ...rest] = v.split('.'); const val = rest.join('.');
    if (op === 'eq') return String(r[k]) === val; if (op === 'gt') return +r[k] > +val; if (op === 'gte') return String(r[k]) >= val; return true; }));
  const INV = [{ producto_id: 1, codigo: '759', nombre: 'Losartán 50 mg', controlado: false, inicial: 10, compras: 20, devoluciones: 2, ventas: 7, retiros: 1, devoluciones_proveedor: 0, ajustes: 0, final: 24, valor_inicial_usd: 20, valor_final_usd: 48, costo_usd: 2, tasa: 100, valor_final_bs: 4800 }];
  const rest = async (st, { m, p, u, b: body, q }) => {
    const uno = (q.headers()['accept'] || '').includes('vnd.pgrst.object');
    const out = x => ({ body: uno ? (Array.isArray(x) ? x[0] : x) : x });
    const tabla = { '/rest/v1/productos': 'productos', '/rest/v1/lotes': 'lotes', '/rest/v1/documentos': 'docs', '/rest/v1/compras': 'compras' }[p];
    if (tabla && m === 'GET') return out(filtrar(T[tabla], u));
    if (p === '/rest/v1/perfiles') return out([{ user_id: 'u-d', nombre: 'José Guerrero' }]);
    if (p === '/rest/v1/proveedores') return out([{ id: 7, nombre: 'Cobeca', rif: 'J-12345678-9', credito_dias: 15, activo: true }]);
    if (p === '/rest/v1/rpc/tasa_del_dia') return { body: 100 };
    if (p.startsWith('/rest/v1/rpc/')) T.rpc.push({ f: p.slice(13), body });
    if (p === '/rest/v1/rpc/registro_inventario') return { body: INV };
    if (p === '/rest/v1/rpc/emitir_nota') { const f = T.docs.find(d => d.id === body.p_factura); const n = { ...f, id: 'nc-1', tipo: 'NC', numero: 1, medio: 'imprenta', numero_fiscal: null, reporte_z: null, afecta_id: f.id, motivo: body.p_motivo, total: 50, base_exenta: 50,
        documento_lineas: body.p_lineas.map((l, k) => ({ renglon: k + 1, descripcion: l.descripcion, cantidad: l.cantidad, precio_unit: l.precio_bs, alicuota: l.alicuota, ref: l.ref })), documento_pagos: [] }; T.docs.push(n); return { body: n }; }
    if (p === '/rest/v1/rpc/nota_compra') { const n = { id: T.seq++, empresa_id: 'E', proveedor: 'Cobeca', tipo: 'NC', numero: body.p_nota.numero, fecha: hoy, tasa: 100, exento_usd: body.p_nota.exento_usd, gravable_usd: 0, iva_usd: 0, total_usd: body.p_nota.exento_usd, pagado_usd: body.p_nota.exento_usd, afecta_id: body.p_factura, motivo: body.p_nota.motivo };
      T.compras.push(n); T.compras[0].pagado_usd += n.total_usd; body.p_items.forEach(i => { T.lotes.find(l => l.id === i.lote_id).cantidad -= i.cantidad; }); return { body: n }; }
  };
  const ctx = await b.newContext(); const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message));
  const st = mock(pg, { tasas: [{ fecha: hoy, tasa: 100 }], rest, empresaExtra: { medio_factura: 'maquina', maquina_marca: 'The Factory', maquina_modelo: 'HKA80', maquina_registro: 'Z7C0012345', maquina_agente: 'simulada', talonario_desde: 1, talonario_hasta: 50 } });
  await pg.goto('http://localhost:8765/farmacia.html'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]');
  await pg.waitForFunction(() => typeof S === 'object' && S.view !== 'login' && P.length === 1 && FX.docs.length === 4, null, { timeout: 8000 }).catch(() => {});

  // 1. Registro de inventario real
  await pg.waitForFunction(() => FX_SYS.inventario.rows().length === 1, null, { timeout: 5000 }).catch(() => {});
  const r = await pg.evaluate(() => { const x = FX_SYS.inventario.rows()[0]; return [x.ini, x.ent, x.dev, x.sal, x.ret, x.fin, x.vf]; });
  ok(JSON.stringify(r) === JSON.stringify([10, 20, 2, 7, 1, 24, 4800]), 'el registro del art. 177 sale de la base (inicial 10 + compras 20 + devoluciones 2 − ventas 7 − retiros 1 = 24)');
  const h = await pg.evaluate(() => FX_SYS.inventario.html());
  ok(h.includes('Devuelto a droguerías') && h.includes('4.800,00') && !h.includes('undefined'), 'la tabla muestra las columnas reales y el valor en Bs');
  ok(await pg.evaluate(() => inv177().length === 1 && inv177()[0].fin === 24), 'la pantalla vieja de libros también usa los datos reales');
  const csv = await pg.evaluate(() => FX_SYS.inventario.csv());
  ok(csv[1][0] === '759' && csv[1][14] === 24, 'y el Excel para el contador');

  // 2. Libro de ventas por Reporte Z
  const lv = await pg.evaluate(() => FX.libroVentas().map(x => [x.nombre, x.num, x.ctrl, x.total]));
  const zr = lv.find(x => /Reporte Z N.° 0087/.test(x[0]));
  ok(zr && zr[1] === '00001501 al 00001502' && zr[2] === 'MH Z7C0012345' && zr[3] === 600, 'consumidor final: un renglón por Reporte Z, del primer al último número, con el registro MH');
  ok(lv.some(x => x[0] === 'Unidad Educativa'), 'la factura con RIF va sola');
  ok(lv.some(x => /falta el Reporte Z/.test(x[0]) && x[3] === 300), 'lo que todavía no tiene Z sale aparte');

  // 3. Nota por descuento: la existencia no sube
  const antes = await pg.evaluate(() => P[0].stock);
  await pg.evaluate(() => { const d = FX.docs.find(x => x.dbId === 'd1501'); openModal(FX.ncModal(d)); });
  await pg.selectOption('#fx-mot', 'Descuento posterior a la venta'); await pg.fill('[data-fxq="0"]', '1'); await pg.click('[data-act="fx-ncgo"]');
  await pg.waitForFunction(() => FX.docs.some(d => d.tipo === 'NC'), null, { timeout: 6000 }).catch(() => {});
  const nc = T.rpc.find(x => x.f === 'emitir_nota');
  ok(nc && nc.body.p_reintegrar === false, 'la nota por descuento no pide devolver mercancía');
  ok(await pg.evaluate(() => P[0].stock) === antes, 'y la pantalla no suma unidades a la existencia');
  await pg.evaluate(() => closeModal());

  // 4. Nota de crédito de la droguería
  await pg.evaluate(() => go('suppliers')); await pg.waitForTimeout(300);
  ok((await pg.textContent('#main, body')).includes('Notas de crédito de droguerías'), 'Proveedores tiene la sección de notas de crédito de droguerías');
  await pg.click('[data-act="fr-ncp"]'); await pg.fill('#ncp-n', 'NC-77'); await pg.fill('#ncp-e', '6');
  await pg.selectOption('#ncp-l', '10'); await pg.fill('#ncp-q', '3'); await pg.click('[data-act="ncp-agregar"]');
  ok((await pg.textContent('#modal')).includes('lote A1'), 'se agregan los productos devueltos con su lote');
  await pg.click('#fr-ncp [type=submit]'); await pg.waitForTimeout(1200);
  const np = T.rpc.find(x => x.f === 'nota_compra');
  ok(np && np.body.p_factura === 50 && np.body.p_nota.numero === 'NC-77' && np.body.p_nota.exento_usd === 6 && np.body.p_items[0].lote_id === 10 && np.body.p_items[0].cantidad === 3, 'la nota va a la base con la factura, el monto y lo devuelto');
  ok(await pg.evaluate(() => P[0].stock) === 21, 'la existencia baja con la devolución a la droguería');
  ok(await pg.evaluate(() => FX_SYS.compras().some(c => c.tipo === 'NC' && c.afecta === '0048213')), 'en el Libro de Compras la nota cita su factura');
  ok(errs.length === 0, 'sin errores en la página' + (errs.length ? ': ' + errs.join(' | ').slice(0, 300) : ''));
  await b.close(); process.exit(fallas ? 1 : 0);
})();
