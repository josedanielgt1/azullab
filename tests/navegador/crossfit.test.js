// CrossFit con datos reales: plan → socio → cobro → entrada → pizarra → recarga (Supabase simulado)
const { chromium } = require('playwright'); const mock = require('./mock');
(async () => {
  const b = await chromium.launch(); let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
  const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Caracas' }).format(new Date());
  const mas = (d, n) => { const x = new Date(d + 'T00:00:00'); x.setDate(x.getDate() + n); return x.toISOString().slice(0, 10); };
  const T = { planes: [], productos_box: [], clases: [], socios: [], asistencias: [], membresias: [], pizarras: [], docs: [], seq: 1, rpc: [] };
  const filtrar = (rows, u) => rows.filter(r => [...u.searchParams].every(([k, v]) => {
    if (['select', 'order', 'limit', 'offset', 'columns', 'on_conflict'].includes(k)) return true;
    const [op, ...rest] = v.split('.'); const val = rest.join('.');
    if (op === 'eq') return String(r[k]) === val; if (op === 'gte') return String(r[k]) >= val; return true; }));
  const rest = async (st, { m, p, u, b: body, q }) => {
    const uno = (q.headers()['accept'] || '').includes('vnd.pgrst.object'), out = x => ({ body: uno ? (Array.isArray(x) ? (x[0] ?? null) : x) : x });
    const t = p.replace('/rest/v1/', '');
    if (p === '/rest/v1/documentos' && m === 'GET') return out(T.docs);
    if (p === '/rest/v1/perfiles') return out([]);
    if (p === '/rest/v1/rpc/tasa_del_dia') return { body: 100 };
    if (T[t] && m === 'GET') return out(filtrar(T[t], u).map(r => t === 'membresias' ? { ...r, documentos: T.docs.find(d => d.id === r.documento_id) } : r));
    if (t === 'pizarras' && m === 'POST') { const i = T.pizarras.findIndex(x => x.fecha === body.fecha); if (i >= 0) T.pizarras[i] = body; else T.pizarras.push(body); return out(body); }
    if (T[t] && m === 'POST') { const r = { activo: true, ...body, id: T.seq++ };
      if (t === 'socios' && T.socios.some(x => x.cedula.replace(/\D/g, '') === r.cedula.replace(/\D/g, ''))) return { status: 409, body: { message: 'duplicate key' } };
      T[t].push(r); return out(r); }
    if (T[t] && m === 'PATCH') { const rs = filtrar(T[t], u); rs.forEach(r => Object.assign(r, body)); return out(rs); }
    if (p === '/rest/v1/rpc/cobrar_membresia') { T.rpc.push(body);
      const so = T.socios.find(x => x.id === body.p_socio), pl = T.planes.find(x => x.id === body.p_plan), desde = so.vence && so.vence > hoy ? so.vence : hoy;
      const d = { id: 'doc-' + (T.docs.length + 1), tipo: 'FAC', origen: 'sistema', numero: T.docs.length + 1, fecha: new Date().toISOString(), cliente_rif: so.cedula, cliente_nombre: so.nombre, tasa: 100, total: pl.precio * 116, total_usd: pl.precio * 1.16, igtf: 0, ref_tipo: 'membresia', documento_lineas: [], documento_pagos: [] };
      T.docs.push(d); const mm = { id: T.seq++, empresa_id: 'E', socio_id: so.id, plan_id: pl.id, desde, hasta: mas(desde, pl.dias), vence_antes: so.vence, precio_usd: pl.precio, metodo: body.p_metodo, documento_id: d.id, creado_en: new Date().toISOString() };
      T.membresias.push(mm); so.vence = mm.hasta; so.plan_id = pl.id; return { body: { membresia: mm, documento: d, socio: so } }; }
  };
  const ctx = await b.newContext(); const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message)); 
  mock(pg, { tipo: 'crossfit', empresa: 'Azullab CrossFit', tasas: [{ fecha: hoy, tasa: 100 }], rest, empresaExtra: { talonario_desde: 1, talonario_hasta: 50 } });
  await pg.goto('http://localhost:8765/crossfit.html'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]');
  await pg.waitForFunction(() => (typeof S === 'object' && S.view !== 'login'), null, { timeout: 8000 });
  ok(await pg.evaluate(() => PLANES.length + SOCIOS.length + PAGOS.length + CLASES.length + ASIS.length) === 0, 'instalación nueva: sin planes, socios, pagos ni clases de muestra');
  ok(await pg.evaluate(() => S.pub) === false, 'la pizarra del día empieza sin publicar');
  const vistas = await pg.evaluate(() => NAV.flatMap(g => g.items.map(i => i[1])));
  for (const v of vistas) { const n = errs.length; await pg.evaluate(x => go(x), v).catch(e => errs.push(v + ': ' + e.message)); if (errs.length > n) console.log('   rota vacía:', v, errs.slice(n).join(' | ').slice(0, 200)); }
  ok(errs.length === 0, `las ${vistas.length} pantallas abren con todo vacío`);
  // Plan, producto y clase desde el panel
  await pg.evaluate(() => go('pagos'));
  const agregar = async (t, vals) => { await pg.click(`[data-act="cfx-edit"][data-t="${t}"]:not([data-i])`); for (const [k, v] of Object.entries(vals)) await pg.fill('#cfx-' + k, v); await pg.click('#cfx-f [type=submit]'); await pg.waitForTimeout(400); };
  await agregar('plan', { n: 'Mensual ilimitado', p: '35', d: '30' });
  await agregar('prod', { n: 'Agua 600 ml', p: '1' });
  await agregar('clase', { h: '06:00', coach: 'Luis', cupo: '14' });
  ok(T.planes.length === 1 && T.planes[0].precio === 35 && T.planes[0].dias === 30, 'el dueño crea un plan');
  ok(T.productos_box.length === 1 && T.clases.length === 1 && T.clases[0].hora === '06:00', 'y un producto y una clase del horario');
  ok(await pg.evaluate(() => PLANES.length === 1 && FX_SYS.PROD.length === 1 && CLASES.length === 1), 'la pantalla los usa');
  // Socio nuevo: queda vencido hasta cobrar
  await pg.evaluate(() => go('socios')); await pg.click('[data-act="nuevo"]'); await pg.fill('#n-n', 'Andrea Peña'); await pg.fill('#n-ci', '24511802');
  await pg.click('#nform [type=submit]'); await pg.waitForFunction(() => SOCIOS[0] && SOCIOS[0]._id, null, { timeout: 6000 }).catch(() => {});
  ok(T.socios.length === 1 && T.socios[0].vence < hoy, 'el socio nuevo se guarda vencido (falta cobrar)');
  // Cobro
  await pg.evaluate(() => { S.pay.s = SOCIOS[0].id; S.pay.plan = PLANES[0].id; S.pay.met = 'Pago móvil'; S.pay.prod = FX_SYS.PROD[0].id; openModal(payModal()); });
  await pg.click('[data-act="pagar"]'); await pg.waitForFunction(() => PAGOS.length === 1 && PAGOS[0]._id, null, { timeout: 6000 }).catch(() => {});
  const r = T.rpc[0];
  ok(r && r.p_socio === T.socios[0].id && r.p_plan === T.planes[0].id && r.p_producto.id === T.productos_box[0].id, 'cobrar llama a cobrar_membresia() con socio, plan y producto');
  ok(await pg.evaluate(() => SOCIOS[0].v) === mas(hoy, 30), 'el vencimiento queda en 30 días desde hoy');
  ok(await pg.evaluate(() => FX.docs.some(d => d.num === '00000001' && d.dbId)), 'la factura sale con el número de la base');
  await pg.evaluate(() => closeModal());
  // Entrada a clase
  await pg.evaluate(() => go('clases')); await pg.fill('#kci', '24511802'); await pg.click('[data-act="entrada"]'); await pg.waitForTimeout(600);
  ok(T.asistencias.length === 1 && T.asistencias[0].clase === '06:00', 'la entrada con cédula se guarda en la base');
  // Pizarra
  await pg.evaluate(() => { S.draft = clone(WOD0); go('pizarra'); }); await pg.click('[data-act="publicar"]'); await pg.waitForTimeout(600);
  ok(T.pizarras.length === 1 && T.pizarras[0].publicada === true && T.pizarras[0].wod.blocks.length > 0, 'publicar la pizarra la guarda en la base');
  ok(T.pizarras[0].reservas['06:00'] && T.pizarras[0].reservas['06:00'][0] === T.socios[0].id, 'con la reserva de la clase');
  // Cobro sin internet
  await ctx.setOffline(true); await pg.waitForTimeout(300);
  await pg.evaluate(() => { S.pay.s = SOCIOS[0].id; S.pay.plan = PLANES[0].id; S.pay.met = 'Pago móvil'; S.pay.prod = ''; openModal(payModal()); });
  await pg.click('[data-act="pagar"]'); await pg.waitForTimeout(500);
  const colaC = await pg.evaluate(() => JSON.parse(localStorage.getItem('cuadre.crossfit.cola') || '[]'));
  ok(colaC.length === 1 && colaC[0].numero === 1 && T.rpc.length === 1, 'sin internet el cobro queda en la cola del equipo con el talonario');
  await pg.evaluate(() => closeModal());
  await ctx.setOffline(false); await pg.waitForFunction(() => !JSON.parse(localStorage.getItem('cuadre.crossfit.cola') || '[]').length, null, { timeout: 8000 }).catch(() => {});
  ok(T.rpc[1] && T.rpc[1].p_origen === 'contingencia' && T.rpc[1].p_numero === 1, 'al volver internet sube como contingencia');
  // Recargar
  await pg.reload(); await pg.waitForFunction(() => (typeof S === 'object' && S.view !== 'login') && SOCIOS.length === 1, null, { timeout: 8000 }).catch(() => {});
  const est = await pg.evaluate(() => ({ pagos: PAGOS.length, asis: ASIS.length, pub: S.pub, res: CLASES[0] && CLASES[0].res.length, cont: SOCIOS[0].asis }));
  ok(est.pagos === 2 && est.asis === 1 && est.pub === true && est.res === 1 && est.cont === 1, 'al recargar siguen ahí socio, pago, entrada, reserva y pizarra publicada ' + JSON.stringify(est));
  for (const v of vistas) { const n = errs.length; await pg.evaluate(x => go(x), v).catch(e => errs.push(v + ': ' + e.message)); if (errs.length > n) console.log('   rota con datos:', v, errs.slice(n).join(' | ').slice(0, 200)); }
  ok(errs.length === 0, 'sin errores de JavaScript ' + errs.join(' | ').slice(0, 300));
  // App del socio: entra con su correo, ve su app y reserva por la función segura
  { const c2 = await b.newContext(); const p2 = await c2.newPage(); const e2 = []; p2.on('pageerror', e => e2.push(e.message)); const R = [];
    mock(p2, { tipo: 'crossfit', empresa: 'Azullab CrossFit', rol: 'socio', tasas: [{ fecha: hoy, tasa: 100 }], rest: async (st, { m, p, b: body, q }) => {
      const uno = (q.headers()['accept'] || '').includes('vnd.pgrst.object');
      if (p === '/rest/v1/socios') return { body: [{ id: 7, empresa_id: 'E', cedula: 'V-24511802', nombre: 'Andrea Peña', vence: mas(hoy, 20), plan_id: 1, datos: {}, user_id: 'u-d' }] };
      if (p === '/rest/v1/clases') return { body: [{ id: 1, hora: '06:00', coach: 'Luis', cupo: 14 }] };
      if (p === '/rest/v1/planes') return { body: [{ id: 1, nombre: 'Mensual', precio: 35, dias: 30 }] };
      if (p === '/rest/v1/pizarras') return { body: uno ? { fecha: hoy, wod: null, publicada: true, reservas: {}, resultados: [] } : [] };
      if (p.startsWith('/rest/v1/rpc/reservar_clase') || p.startsWith('/rest/v1/rpc/anotar_resultado')) { R.push({ p, body }); return { body: { reservado: true } }; }
      if (m === 'GET' && p.startsWith('/rest/v1/') && !p.includes('rpc')) return { body: uno ? null : [] };
    } });
    await p2.goto('http://localhost:8765/crossfit.html#socio'); await p2.fill('#lu', 'andrea@correo.com'); await p2.fill('#lp', 'clave-buena'); await p2.click('#loginForm [type=submit]');
    await p2.waitForFunction(() => (typeof S === 'object' && S.view !== 'login'), null, { timeout: 8000 }).catch(() => {});
    ok(await p2.evaluate(() => S.role === 'Socio' && S.view === 'app' && S.me === 'S7'), 'el socio entra con su correo directo a su app');
    await p2.evaluate(() => { const c = CLASES.find(x => x.h === '06:00'); c.res.push(S.me); render(); }); await p2.click('body'); await p2.waitForTimeout(500);
    ok(R.some(r => r.p.endsWith('reservar_clase') && r.body.p_hora === '06:00'), 'reservar va por la función segura (no toca la pizarra)');
    await p2.evaluate(() => { RES.push({ s: S.me, t: '8:42', rx: true }); render(); }); await p2.click('body'); await p2.waitForTimeout(500);
    ok(R.some(r => r.p.endsWith('anotar_resultado') && r.body.p_tiempo === '8:42'), 'anotar su resultado también');
    ok(e2.length === 0, 'app del socio sin errores de JavaScript ' + e2.join(' | ').slice(0, 200)); await c2.close(); }
  await b.close(); process.exit(fallas ? 1 : 0);
})();
