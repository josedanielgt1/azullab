// Laboratorio con datos reales: catálogo base → paciente → orden con factura → toma → recarga (Supabase simulado)
const { chromium } = require('playwright'); const mock = require('./mock');
(async () => {
  const b = await chromium.launch(); let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
  const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Caracas' }).format(new Date());
  const T = { examenes: [], perfiles_lab: [], medicos: [], pacientes: [], ordenes: [], docs: [], colecciones: [], compras: [], seq: 1, rpc: [], patch: [] };
  const filtrar = (rows, u) => rows.filter(r => [...u.searchParams].every(([k, v]) => {
    if (['select', 'order', 'limit', 'offset', 'columns', 'on_conflict'].includes(k)) return true;
    const [op, ...rest] = v.split('.'); const val = rest.join('.');
    if (op === 'eq') return String(r[k]) === val; if (op === 'gte') return String(r[k]) >= val; return true; }));
  const rest = async (st, { m, p, u, b: body, q }) => {
    const uno = (q.headers()['accept'] || '').includes('vnd.pgrst.object'), out = x => ({ body: uno ? (Array.isArray(x) ? x[0] : x) : x });
    const t = p.replace('/rest/v1/', '');
    if (p === '/rest/v1/documentos' && m === 'GET') return out(T.docs);
    if (p === '/rest/v1/perfiles') return out([{ user_id: 'u-d', nombre: 'José Guerrero' }]);
    if (p === '/rest/v1/colecciones' && m === 'GET') return out(filtrar(T.colecciones, u));
    if (p === '/rest/v1/colecciones' && m === 'POST') { T.colecciones = T.colecciones.filter(c => c.nombre !== body.nombre).concat([body]); return out(body); }
    if (p === '/rest/v1/rpc/tasa_del_dia') return { body: 100 };
    if (T[t] && m === 'GET') return out(filtrar(T[t], u).map(r => t === 'ordenes' ? { ...r, documentos: T.docs.find(d => d.id === r.documento_id) } : r));
    if (T[t] && m === 'POST') { const rows = (Array.isArray(body) ? body : [body]).map(r => ({ activo: true, ...r, id: T.seq++ }));
      if (t === 'pacientes' && rows.some(r => r.cedula && T.pacientes.some(x => x.cedula === r.cedula))) return { status: 409, body: { message: 'duplicate key value violates unique constraint' } };
      T[t].push(...rows); return out(Array.isArray(body) ? rows : rows[0]); }
    if (T[t] && m === 'PATCH') { const rs = filtrar(T[t], u); rs.forEach(r => Object.assign(r, body)); T.patch.push({ t, body }); return out(rs); }
    if (p === '/rest/v1/rpc/registrar_compra') { const f = body.p_factura; if (T.compras.some(c => c.numero === f.numero)) return { status: 409, body: { message: 'duplicate key' } };
      T.compras.push({ id: T.seq++, empresa_id: 'E', tipo: 'FAC', proveedor: f.proveedor, rif: 'J-12345678-9', numero: f.numero, control: f.control, fecha: f.fecha, tasa: 100, exento_usd: f.exento_bs / 100, gravable_usd: f.gravable_bs / 100, datos: { exento_bs: f.exento_bs, gravable_bs: f.gravable_bs, retencion: f.retencion } }); return { body: T.compras[T.compras.length - 1] }; }
    if (p === '/rest/v1/rpc/crear_orden') { T.rpc.push(body);
      const tot = body.p_items.reduce((s, i) => s + (i.k === 'perf' ? T.perfiles_lab.find(x => x.codigo === i.c) : T.examenes.find(x => x.codigo === i.c)).precio, 0);
      const d = { id: 'doc-1', tipo: 'FAC', origen: 'sistema', numero: T.docs.length + 1, numero_control: null, fecha: new Date().toISOString(), cliente_rif: 'V-9876543', cliente_nombre: 'María', tasa: 100, total: tot * 100, total_usd: tot, igtf: 0, ref_tipo: 'orden', creado_por: 'u-d', documento_lineas: [], documento_pagos: [] };
      T.docs.push(d);
      const o = { id: T.seq++, empresa_id: 'E', numero: 'L-' + String(T.ordenes.length + 1).padStart(4, '0'), paciente_id: body.p_paciente, items: body.p_items, total_usd: tot, medico: body.p_medico, urgente: body.p_urgente, visita: body.p_visita, estado: 'Por tomar', datos: {}, documento_id: d.id, creado_por: 'u-d', creado_en: new Date().toISOString() };
      T.ordenes.push(o); return { body: { orden: o, documento: d } }; }
  };
  const ctx = await b.newContext(); const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message));
  mock(pg, { tipo: 'laboratorio', empresa: 'Azullab Laboratorio', tasas: [{ fecha: hoy, tasa: 100 }], rest });
  const entrar = async () => { await pg.goto('http://localhost:8765/laboratorio.html'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]');
    await pg.waitForFunction(() => !document.getElementById('loginForm'), null, { timeout: 8000 }); };
  await entrar();
  ok(await pg.evaluate(() => EX.length + PERF.length + PATS.length + ORD.length + REAC.length + Object.keys(HIST).length) === 0, 'instalación nueva: sin exámenes, pacientes, órdenes, reactivos ni historial de muestra');
  ok(await pg.evaluate(() => FX_SYS.compras().length === 0 && FX_SYS.islr().length === 0 && FX_SYS.excedente === 0), 'sin libro de compras, retenciones ni excedente de muestra');
  const vistas = await pg.evaluate(() => NAV.flatMap(g => g.items.map(i => i[1])));
  for (const v of vistas) { const n = errs.length; await pg.evaluate(x => go(x), v).catch(e => errs.push(v + ': ' + e.message)); if (errs.length > n) console.log('   rota vacía:', v, errs.slice(n).join(' | ').slice(0, 200)); }
  ok(errs.length === 0, `las ${vistas.length} pantallas abren con todo vacío`);
  await pg.evaluate(() => go('catalogo')); await pg.click('[data-act="lab-base"]');
  await pg.waitForFunction(() => EX.length > 0, null, { timeout: 6000 }).catch(() => {});
  ok(T.examenes.length >= 20 && T.perfiles_lab.length > 3 && await pg.evaluate(() => EX.length) === T.examenes.length, `el dueño carga el catálogo base (${T.examenes.length} exámenes, ${T.perfiles_lab.length} perfiles)`);
  ok(T.examenes.find(e => e.codigo === 'HEM').parametros.ps.length > 3, 'con sus parámetros y valores de referencia');
  // Paciente nuevo
  await pg.evaluate(() => { go('recepcion'); PATS.push({ id: 'N1', ci: 'V-9876543', n: 'María Rondón', s: 'F', b: '1968-04-12', tel: '0414', sangre: 'O+' }); S.ord.pat = 'N1'; render(); });
  await pg.click('body'); await pg.waitForFunction(() => PATS[0].id.startsWith('P'), null, { timeout: 6000 }).catch(() => {});
  ok(T.pacientes.length === 1 && T.pacientes[0].datos.sangre === 'O+', 'el paciente nuevo se guarda con su ficha');
  ok(await pg.evaluate(() => S.ord.pat === PATS[0].id && PATS[0].id === 'P' + PATS[0]._id), 'la orden en curso queda con el número de la base');
  // Orden con su factura
  await pg.evaluate(() => { S.ord.items = [{ k: 'perf', c: 'CHK' }]; S.ord.med = '1'; S.pay = 'Pago móvil'; openModal(payModal()); });
  await pg.click('[data-act="emit"]'); await pg.waitForFunction(() => ORD.length === 1 && ORD[0]._id, null, { timeout: 6000 }).catch(() => {});
  const r = T.rpc[0];
  ok(r && r.p_items[0].c === 'CHK' && r.p_paciente === T.pacientes[0].id && r.p_pagos[0].metodo === 'Pago móvil', 'cobrar llama a crear_orden() con paciente, exámenes y pago');
  ok(await pg.evaluate(() => ORD[0].n) === 'L-0001', 'la orden toma el número que dio la base');
  ok(await pg.evaluate(() => FX.docs.some(d => d.num === '00000001' && d.dbId === 'doc-1')), 'y su factura el número de la base');
  await pg.evaluate(() => closeModal()); await pg.waitForTimeout(500);
  ok(T.ordenes[0].datos.pay === 'Pago móvil', 'se guarda cómo pagó');
  // Toma de muestras
  await pg.evaluate(() => { const o = ORD[0]; o.st = 'En proceso'; o.toma = '07:05'; render(); }); await pg.click('body'); await pg.waitForTimeout(500);
  ok(T.ordenes[0].estado === 'En proceso' && T.ordenes[0].datos.toma === '07:05', 'la toma de muestras se guarda en la base');
  // Reactivos
  await pg.evaluate(() => go('reactivos')); await pg.click('[data-act="lab-reac"]');
  for (const [k, v] of Object.entries({ 'rq-n': 'Reactivo de glucosa', 'rq-l': 'gl2611a', 'rq-e': '2027-03-31', 'rq-q': '420', 'rq-d': '22' })) await pg.fill('#' + k, v);
  await pg.click('#lab-reac-f [type=submit]'); await pg.waitForTimeout(600);
  const rc = T.colecciones.find(c => c.nombre === 'equipo_reactivos');
  ok(rc && rc.datos[0].l === 'GL2611A' && rc.datos[0].q === 420, 'la entrada de reactivo se guarda en la base');
  // Editar examen: precio y reactivo que gasta
  await pg.evaluate(() => go('catalogo')); await pg.click('[data-act="lab-ex"][data-c="GLI"]');
  await pg.fill('#ce-p', '3'); await pg.selectOption('#ce-rn', 'Reactivo de glucosa'); await pg.fill('#ce-rq', '1');
  await pg.click('#lab-ex-f [type=submit]'); await pg.waitForTimeout(600);
  const gli = T.examenes.find(e => e.codigo === 'GLI');
  ok(gli.precio === 3 && gli.parametros.reac && gli.parametros.reac.n === 'Reactivo de glucosa', 'el dueño cambia el precio y el reactivo del examen');
  ok(gli.parametros.ps.length >= 1 && gli.parametros.ps[0].r, 'conserva los parámetros con su referencia');
  // Validar descuenta el reactivo
  await pg.evaluate(() => { const o = ORD[0]; o.st = 'Validado'; o.val = { by: 'Bio', t: '10:00' }; render(); }); await pg.click('body'); await pg.waitForTimeout(700);
  const rc2 = T.colecciones.find(c => c.nombre === 'equipo_reactivos');
  ok(rc2 && rc2.datos[0].q === 419, 'al validar, se descuenta el reactivo que gastó (420 → 419)');
  await pg.evaluate(() => { ORD[0].st = 'Validado'; render(); }); await pg.click('body'); await pg.waitForTimeout(400);
  ok(T.colecciones.find(c => c.nombre === 'equipo_reactivos').datos[0].q === 419, 'y no se descuenta dos veces');
  // Factura de compra con retención de ISLR
  await pg.evaluate(() => go('libros')); await pg.click('[data-act="cx-compra"]');
  for (const [k, v] of Object.entries({ 'cx-p': 'Distribuidora de reactivos', 'cx-r': 'j123456789', 'cx-n': '0004521', 'cx-c': '00-31877', 'cx-g': '1.000,00' })) await pg.fill('#' + k, v);
  await pg.selectOption('#cx-k', 'ser'); await pg.click('#cx-compra-f [type=submit]'); await pg.waitForTimeout(600);
  ok(T.compras.length === 1 && T.compras[0].datos.gravable_bs === 1000, 'el dueño registra la factura de compra (base 1.000 Bs)');
  ok(await pg.evaluate(() => FX_SYS.compras().length === 1 && FX_SYS.compras()[0].bg === 1000), 'y entra al Libro de Compras');
  ok(await pg.evaluate(() => FX.islr().length === 1 && FX.islr()[0].k === 'ser'), 'con su retención de ISLR');
  // Excedente del mes anterior
  await pg.evaluate(() => go('config')); await pg.fill('#fx-f-rif', 'J-50134578-3'); await pg.fill('#fx-f-excedente', '1.500,00'); await pg.click('#fx-dform [type=submit]'); await pg.waitForTimeout(600);
  ok(T.colecciones.some(c => c.nombre === 'privado_fiscal' && c.datos.excedente === 1500) && await pg.evaluate(() => FX_SYS.excedente) === 1500, 'el excedente del mes anterior se guarda y entra al borrador de IVA');
  // Recargar
  await pg.reload(); await pg.waitForFunction(() => !document.getElementById('loginForm') && ORD.length === 1 && PATS.length === 1, null, { timeout: 8000 }).catch(() => {});
  ok(await pg.evaluate(() => ORD[0].st === 'Validado' && ORD[0].pat === PATS[0].id && ORD[0].fac === '00000001' && EX.length >= 20 && MEDICOS.length >= 1 && REAC.length === 1 && EX.find(e => e.c === 'GLI').p === 3), 'al recargar siguen ahí paciente, orden, estado, factura, catálogo y reactivos');
  for (const v of vistas) { const n = errs.length; await pg.evaluate(x => go(x), v).catch(e => errs.push(v + ': ' + e.message)); if (errs.length > n) console.log('   rota con datos:', v, errs.slice(n).join(' | ').slice(0, 200)); }
  ok(errs.length === 0, 'sin errores de JavaScript ' + errs.join(' | ').slice(0, 300));
  await b.close(); process.exit(fallas ? 1 : 0);
})();
