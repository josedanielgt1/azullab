// Farmacia con el AGENTE DE VERDAD (agente/, en Go) y su impresora simulada (-puerto sim):
// la caja web le habla al agente por http://127.0.0.1:7123 con CORS, el agente arma las tramas del
// protocolo de The Factory HKA y devuelve el número de la memoria fiscal. Supabase simulado.
// Si en el equipo no está Go, la prueba se salta.
const { chromium } = require('playwright'); const mock = require('./mock');
const { execFileSync, spawn } = require('child_process'); const fs = require('fs'); const os = require('os'); const path = require('path');
(async () => {
  try { execFileSync('go', ['version'], { stdio: 'ignore' }); } catch (_) { console.log('salta  sin Go no se puede compilar el agente'); return; }
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'agente-')); const exe = path.join(dir, 'agente');
  execFileSync('go', ['build', '-o', exe, '.'], { cwd: path.join(__dirname, '../../agente') });
  fs.writeFileSync(path.join(dir, 'agente.json'), JSON.stringify({ puerto: 'sim', escucha: '127.0.0.1:7123', origenes: ['http://localhost:8765'], flag21: 30, flag50: 0 }));
  const ag = spawn(exe, ['-servir', '-puerto', 'sim', '-dir', dir], { stdio: 'ignore' });
  const fin = () => { try { ag.kill(); } catch (_) {} };
  for (let i = 0; i < 40; i++) { try { await fetch('http://127.0.0.1:7123/estado'); break; } catch (_) { await new Promise(r => setTimeout(r, 150)); } }
    const b = await chromium.launch(); let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
    const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Caracas' }).format(new Date());
    const T = { productos: [{ id: 1, empresa_id: 'E', codigo: '759', codigos_alt: [], nombre: 'Losartán 50 mg', principio_activo: 'Losartán', laboratorio: '—', presentacion: 'Caja x 30', seccion: 'Otros', iva: 'E', costo: 2, margen: 50, precio: 3, pmvp: null, por_lote: false, minimo: 5, rx: false, controlado: false, historial: [], activo: true }],
      lotes: [{ id: 10, empresa_id: 'E', producto_id: 1, lote: 'A1', vence: '2030-01-01', cantidad: 50, costo: 2, precio: null }],
      docs: [], reportes_z: [], maquina_eventos: [], talonario_usados: [], rpc: [], seq: 100 };
    const AG = { pedidos: [], falla: null, fac: 1500, z: 86 };
    const filtrar = (rows, u) => rows.filter(r => [...u.searchParams].every(([k, v]) => {
      if (['select', 'order', 'limit', 'offset', 'columns', 'on_conflict'].includes(k)) return true;
      const [op, ...rest] = v.split('.'); const val = rest.join('.');
      if (op === 'eq') return String(r[k]) === val; if (op === 'gt') return +r[k] > +val; if (op === 'gte') return String(r[k]) >= val; return true; }));
    const nuevoDoc = (body, tipo, extra) => { const n = T.docs.filter(d => d.tipo === tipo).length + 1;
      const lineas = tipo === 'FAC' ? body.p_items.map((i, k) => ({ renglon: k + 1, descripcion: 'Losartán 50 mg', cantidad: i.cantidad, precio_unit: i.precio_usd * 100, alicuota: 'E', ref: { producto_id: i.producto_id } })) : body.p_lineas.map((l, k) => ({ renglon: k + 1, descripcion: l.descripcion, cantidad: l.cantidad, precio_unit: l.precio_bs, alicuota: l.alicuota, ref: l.ref }));
      const tot = lineas.reduce((t, l) => t + l.cantidad * l.precio_unit, 0);
      const d = { id: tipo.toLowerCase() + '-' + n, empresa_id: 'E', tipo, origen: 'sistema', numero: n, numero_control: null, estado: 'pendiente_imprenta', medio: 'maquina', maquina_registro: 'Z7C0012345', numero_fiscal: null, reporte_z: null,
        fecha: new Date().toISOString(), cliente_rif: 'V-00000000', cliente_nombre: 'Consumidor final', tasa: 100, base_exenta: tot, base_general: 0, iva_general: 0, base_reducida: 0, iva_reducida: 0, igtf: 0, total: tot, total_usd: tot / 100,
        ref_tipo: tipo === 'FAC' ? 'venta' : null, creado_por: 'u-d', afecta_id: null, motivo: null, documento_lineas: lineas, documento_pagos: tipo === 'FAC' ? body.p_pagos.map(x => ({ metodo: x.metodo, monto_bs: x.monto_bs })) : [], ...extra };
      if (tipo === 'FAC') body.p_items.forEach(i => { T.lotes[0].cantidad -= i.cantidad; });
      T.docs.push(d); return d; };
    const rest = async (st, { m, p, u, b: body, q }) => {
      const uno = (q.headers()['accept'] || '').includes('vnd.pgrst.object');
      const out = x => ({ body: uno ? (Array.isArray(x) ? x[0] : x) : x });
      const tabla = { '/rest/v1/productos': 'productos', '/rest/v1/lotes': 'lotes', '/rest/v1/documentos': 'docs', '/rest/v1/reportes_z': 'reportes_z', '/rest/v1/maquina_eventos': 'maquina_eventos', '/rest/v1/talonario_usados': 'talonario_usados' }[p];
      if (tabla && m === 'GET') { let rs = filtrar(T[tabla], u); if (tabla === 'reportes_z') rs = rs.slice().sort((a, c) => c.numero - a.numero); if (tabla === 'docs' && (u.searchParams.get('order') || '').startsWith('numero_fiscal')) rs = rs.filter(d => d.numero_fiscal).sort((a, c) => c.numero_fiscal - a.numero_fiscal); return out(rs); }
      if (tabla && m === 'POST') { const r = { ...body, id: T.seq++, fecha: hoy }; T[tabla].push(r); return out(r); }
      if (p === '/rest/v1/perfiles') return out([{ user_id: 'u-d', nombre: 'José Guerrero' }]);
      if (p === '/rest/v1/rpc/tasa_del_dia') return { body: 100 };
      if (p.startsWith('/rest/v1/rpc/')) T.rpc.push({ f: p.slice(13), body });
      if (p === '/rest/v1/rpc/vender') return { body: nuevoDoc(body, 'FAC') };
      if (p === '/rest/v1/rpc/emitir_nota') { const f = T.docs.find(d => d.id === body.p_factura); return { body: nuevoDoc(body, body.p_tipo, { afecta_id: f.id, motivo: body.p_motivo }) }; }
      if (p === '/rest/v1/rpc/registrar_maquina') { const d = T.docs.find(x => x.id === body.p_doc); if (d.estado !== 'pendiente_imprenta') return { status: 400, body: { message: 'Ese documento ya quedó impreso' } };
        Object.assign(d, { numero_fiscal: body.p_numero, estado: 'emitido', imprenta_resp: body.p_resp }); return { body: d }; }
      if (p === '/rest/v1/rpc/registrar_falla_maquina') { const d = T.docs.find(x => x.id === body.p_doc);
        Object.assign(d, { medio: 'talonario', estado: 'emitido', numero_control: '01-' + String(body.p_numero).padStart(8, '0') }); T.talonario_usados.push({ empresa_id: 'E', numero: body.p_numero }); return { body: d }; }
      if (p === '/rest/v1/rpc/jornada_maquina') { const ds = T.docs.filter(d => d.medio === 'maquina' && d.estado === 'emitido' && !d.reporte_z);
        return { body: { cant_fac: ds.filter(d => d.tipo === 'FAC').length, cant_nc: ds.filter(d => d.tipo === 'NC').length, total: ds.reduce((t, d) => t + (d.tipo === 'NC' ? -1 : 1) * d.total, 0), exento: 0, base_general: 0, iva_general: 0, pendientes: T.docs.filter(d => d.medio === 'maquina' && d.estado === 'pendiente_imprenta').length } }; }
      if (p === '/rest/v1/rpc/registrar_reporte_z') { const z = { id: T.seq++, empresa_id: 'E', maquina_registro: body.p_registro, numero: body.p_z.numero, dia: hoy, fecha: new Date().toISOString(), cant_fac: body.p_z.cant_fac, cant_nc: 0, total: body.p_z.total, sis_cant_fac: body.p_z.cant_fac, sis_cant_nc: 0, sis_total: body.p_z.total, cuadra: true };
        T.reportes_z.push(z); T.docs.filter(d => d.medio === 'maquina' && d.numero_fiscal).forEach(d => { d.reporte_z = z.numero; }); return { body: z }; }
      if (p === '/rest/v1/rpc/vender_impresa') return { body: nuevoDoc({ p_items: body.p_items, p_pagos: body.p_pagos }, 'FAC', { numero_fiscal: body.p_numero, estado: 'emitido' }) };
    };
    const ctx = await b.newContext(); const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message));
  const st = mock(pg, { tasas: [{ fecha: hoy, tasa: 100 }], rest, empresaExtra: { medio_factura: 'maquina', maquina_marca: 'Aclas', maquina_modelo: 'PP9 Plus', maquina_registro: 'ZZP0000001', maquina_agente: 'http://127.0.0.1:7123', iva_general: 16, iva_reducida: 8, igtf: 0 } });
  await pg.goto('http://localhost:8765/farmacia.html'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]');
  await pg.waitForFunction(() => typeof S === 'object' && S.view !== 'login' && P.length === 1 && S.medio === 'maquina', null, { timeout: 8000 }).catch(() => {});
  await pg.waitForFunction(() => MAQ.lista === true, null, { timeout: 6000 }).catch(() => {});
  ok(await pg.evaluate(() => MAQ.lista === true && MAQ.estado === 'Conectada'), 'la caja ve el agente y la impresora conectada');

  const vender = async () => { await pg.evaluate(() => { closeModal(); go('pos'); }); await pg.click('[data-act="add"][data-id="1"]'); await pg.click('[data-act="checkout"]'); await pg.click('[data-act="addpay"]'); await pg.click('[data-act="emit"]'); };
  await vender();
  await pg.waitForFunction(() => document.getElementById('modal').textContent.includes('00001501'), null, { timeout: 10000 }).catch(() => {});
  const rm = T.rpc.find(r => r.f === 'registrar_maquina');
  ok(rm && rm.body.p_numero === 1501 && rm.body.p_registro === 'ZZP0000001', 'el agente imprime y devuelve el número de la memoria fiscal (1501), que se guarda en la base');
  await vender();
  await pg.waitForFunction(() => document.getElementById('modal').textContent.includes('00001502'), null, { timeout: 10000 }).catch(() => {});
  ok(T.rpc.filter(r => r.f === 'registrar_maquina').map(r => r.body.p_numero).join() === '1501,1502', 'la segunda venta sale con el siguiente número');

  await pg.evaluate(() => { closeModal(); go('fiscal'); }); await pg.click('[data-act="repx"]'); await pg.waitForTimeout(1200);
  ok((await pg.textContent('#modal')).includes('Reporte X'), 'el Reporte X sale por el agente');
  await pg.evaluate(() => closeModal());
  await pg.click('[data-act="repz"]'); await pg.waitForSelector('[data-act="mq-zgo"]', { timeout: 5000 }).catch(() => {});
  await pg.click('[data-act="mq-zgo"]'); await pg.waitForTimeout(6000);
  const rz = T.rpc.find(r => r.f === 'registrar_reporte_z');
  ok(rz && rz.body.p_z.numero === 87 && rz.body.p_z.cant_fac === 2 && rz.body.p_z.fac_desde === 1501 && rz.body.p_z.fac_hasta === 1502 && rz.body.p_z.total === 600 && rz.body.p_registro === 'ZZP0000001',
    'el Reporte Z del agente trae número, rango de facturas y total, y se guarda en la base');

  // Otra página de internet no puede usar el agente
  const ajena = await fetch('http://127.0.0.1:7123/estado', { headers: { Origin: 'https://otra-pagina.com' } });
  ok(ajena.status === 403, 'una página que no es Cuadre no puede usar el agente');
  ok(!errs.length, 'sin errores en la página' + (errs.length ? ': ' + errs.join(' | ') : ''));
  await b.close(); fin(); fs.rmSync(dir, { recursive: true, force: true });
  if (fallas) { console.log(fallas + ' falla(s)'); process.exit(1); }
})().catch(e => { console.error(e); process.exit(1); });
