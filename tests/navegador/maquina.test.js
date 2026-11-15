// Farmacia con máquina fiscal: venta impresa, falla de la impresora (reintentar, talonario, pendiente),
// Reporte X y Z, venta sin internet y configuración. Supabase y el agente de la impresora simulados.
const { chromium } = require('playwright'); const mock = require('./mock');
(async () => {
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
  // El agente local de la impresora
  await pg.route('http://127.0.0.1:7123/**', async r => {
    const q = r.request(), ruta = new URL(q.url()).pathname; let c = null; try { c = JSON.parse(q.postData() || 'null'); } catch (_) {}
    AG.pedidos.push({ ruta, c });
    const j = x => r.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(x) });
    if (ruta === '/estado') return j({ ok: true, registro: 'Z7C0012345', modelo: 'HKA80' });
    if (AG.falla) return j({ ok: false, error: AG.falla });
    if (ruta === '/documento') return j({ ok: true, numero: ++AG.fac, registro: 'Z7C0012345', fecha: new Date().toISOString() });
    if (ruta === '/reporte-x') return j({ ok: true, registro: 'Z7C0012345', cant_fac: 2, cant_nc: 0, total: 600 });
    if (ruta === '/reporte-z') return j({ ok: true, registro: 'Z7C0012345', numero: ++AG.z, fac_desde: 1501, fac_hasta: 1502, cant_fac: 2, total: 600, texto: 'REPORTE Z' });
    return j({ ok: false, error: 'ruta' });
  });
  const st = mock(pg, { tasas: [{ fecha: hoy, tasa: 100 }], rest, empresaExtra: { medio_factura: 'maquina', maquina_marca: 'The Factory', maquina_modelo: 'HKA80', maquina_registro: 'Z7C0012345', maquina_agente: 'http://127.0.0.1:7123', iva_general: 16, iva_reducida: 8, igtf: 0 } });
  await pg.goto('http://localhost:8765/farmacia.html'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]');
  await pg.waitForFunction(() => typeof S === 'object' && S.view !== 'login' && P.length === 1 && S.medio === 'maquina', null, { timeout: 8000 }).catch(() => {});
  ok(await pg.evaluate(() => S.medio) === 'maquina', 'la farmacia con máquina configurada entra en modo máquina fiscal');
  ok(await pg.evaluate(() => MAQ.registro === 'Z7C0012345' && MAQ.modelo === 'The Factory HKA80'), 'con la marca, el modelo y el registro de la base');

  const vender = async () => { await pg.evaluate(() => { closeModal(); go('pos'); }); await pg.click('[data-act="add"][data-id="1"]'); await pg.click('[data-act="checkout"]'); await pg.click('[data-act="addpay"]'); await pg.click('[data-act="emit"]'); };
  // 1. Venta impresa
  await vender();
  await pg.waitForFunction(() => document.getElementById('modal').textContent.includes('00001501'), null, { timeout: 8000 }).catch(() => {});
  const ped = AG.pedidos.find(x => x.ruta === '/documento');
  ok(ped && ped.c.tipo === 'FAC' && ped.c.lineas[0].precio === 300 && ped.c.lineas[0].alicuota === 'E' && ped.c.cliente.rif === 'V-00000000', 'la caja le manda la factura de la base al agente (renglones en Bs, alícuota y cliente)');
  const rm = T.rpc.find(r => r.f === 'registrar_maquina');
  ok(rm && rm.body.p_numero === 1501 && rm.body.p_registro === 'Z7C0012345', 'el número de la memoria fiscal se guarda en la base');
  const tk = await pg.textContent('#modal');
  ok(tk.includes('00001501') && tk.includes('MH  Z7C0012345') && tk.includes('SENIAT'), 'el ticket sale con el número fiscal y el registro MH');

  // 2. Sin papel → reintentar
  AG.falla = 'Sin papel';
  await vender();
  await pg.waitForSelector('[data-act="mq-reint"]', { timeout: 6000 }).catch(() => {});
  ok((await pg.textContent('#modal')).includes('Sin papel'), 'si la impresora falla, la caja dice qué pasó');
  AG.falla = null; await pg.click('[data-act="mq-reint"]');
  await pg.waitForFunction(() => document.getElementById('modal').textContent.includes('00001502'), null, { timeout: 6000 }).catch(() => {});
  ok((await pg.textContent('#modal')).includes('00001502'), 'al reintentar, imprime y sigue');

  // 3. Impresora dañada → pendiente (sin talonario), la falla queda en el libro de la máquina
  AG.falla = 'Error de memoria fiscal';
  await vender();
  await pg.waitForSelector('[data-act="mq-pend"]', { timeout: 6000 }).catch(() => {});
  ok(!(await pg.$('#mq-tal')) && !(await pg.$('[data-act="mq-tal"]')) && !(await pg.textContent('#modal')).toLowerCase().includes('talonario'), 'si la impresora se daña, no se ofrece talonario');
  await pg.click('[data-act="mq-pend"]'); await pg.waitForTimeout(800);
  const pend = T.docs.filter(d => d.estado === 'pendiente_imprenta');
  ok(pend.length === 1, 'puede quedar pendiente de imprimir (la venta ya está en la base)');
  ok(T.maquina_eventos.some(e => e.tipo === 'falla' && e.detalle.includes('Error de memoria fiscal') && e.detalle.includes('pendiente')), 'la falla queda anotada en el libro de la máquina');
  ok(!T.rpc.some(r => r.f === 'registrar_falla_maquina'), 'nada sale del talonario');

  // 4. Imprimir lo pendiente desde Módulo fiscal
  AG.falla = null;
  await pg.evaluate(() => { closeModal(); go('fiscal'); }); await pg.waitForTimeout(800);
  await pg.evaluate(() => Cuadre.maquina.refrescar().then(() => render())); await pg.waitForTimeout(300);
  ok((await pg.textContent('#main, body')).includes('Pendientes de imprimir') && await pg.$('[data-act="mq-repend"]') !== null, 'Módulo fiscal muestra lo pendiente de imprimir');
  await pg.click('[data-act="mq-repend"]'); await pg.waitForTimeout(1200);
  ok(pend[0].estado === 'emitido' && pend[0].numero_fiscal === 1503, 'y desde ahí se imprime');

  // 5. Nota de crédito por la máquina
  await pg.evaluate(() => { const d = FX.docs.find(x => x.tipo === 'FAC' && x.num === '00001501'); openModal(FX.ncModal(d)); });
  await pg.fill('[data-fxq="0"]', '1'); await pg.click('[data-act="fx-ncgo"]');
  await pg.waitForFunction(() => FX.docs.some(d => d.tipo === 'NC'), null, { timeout: 6000 }).catch(() => {});
  const pn = AG.pedidos.filter(x => x.ruta === '/documento').pop();
  ok(pn && pn.c.tipo === 'NC' && pn.c.afecta && pn.c.afecta.numero === 1501, 'la nota de crédito la imprime la máquina citando su factura');
  ok(await pg.evaluate(() => FX.docs.find(d => d.tipo === 'NC').num) === '00001504', 'y queda con su número fiscal');
  await pg.evaluate(() => closeModal());

  // 6. Reporte X y Z
  await pg.evaluate(() => go('fiscal')); await pg.click('[data-act="repx"]'); await pg.waitForTimeout(800);
  ok((await pg.textContent('#modal')).includes('Reporte X') && (await pg.textContent('#modal')).includes('Impresora'), 'el Reporte X compara la impresora con Cuadre');
  await pg.evaluate(() => closeModal());
  await pg.click('[data-act="repz"]'); await pg.waitForSelector('[data-act="mq-zgo"]', { timeout: 5000 }).catch(() => {});
  await pg.click('[data-act="mq-zgo"]'); await pg.waitForTimeout(1500);
  const rz = T.rpc.find(r => r.f === 'registrar_reporte_z');
  ok(rz && rz.body.p_z.numero === 87 && rz.body.p_z.total === 600 && rz.body.p_registro === 'Z7C0012345', 'el Reporte Z de la máquina se guarda en la base');
  ok((await pg.textContent('#modal')).includes('Cuadra'), 'y dice si cuadra');
  await pg.evaluate(() => closeModal());
  await pg.click('[data-act="repz"]'); await pg.waitForTimeout(500);
  ok((await pg.textContent('#toast')).includes('ya se hizo'), 'un segundo Z el mismo día no se hace');
  await pg.evaluate(() => Cuadre.cargarDocumentos().then(() => Cuadre.farmacia.alCambiarDocs()));
  ok(await pg.evaluate(() => LIBRO.some(r => /^Reporte Z N.° 0087/.test(r[1]) && r[3] === 'Consumidor final')), 'el libro de ventas pone las facturas a consumidor final en un renglón por Z');

  // 7. Sin internet: la máquina imprime igual
  await pg.evaluate(() => { Object.defineProperty(navigator, 'onLine', { configurable: true, get: () => false }); });
  const antes = T.rpc.filter(r => r.f === 'vender').length;
  await vender(); await pg.waitForTimeout(1200);
  const cola = await pg.evaluate(() => Cuadre.leerLocal('cola'));
  ok(cola.length === 1 && cola[0].maquina === 'Z7C0012345' && cola[0].numero === 1505, 'sin internet imprime y guarda la venta en el equipo con su número fiscal');
  ok(T.rpc.filter(r => r.f === 'vender').length === antes, 'sin llamar a la base');
  await pg.evaluate(() => { Object.defineProperty(navigator, 'onLine', { configurable: true, get: () => true }); return Cuadre.subirCola(); }); await pg.waitForTimeout(800);
  const vi = T.rpc.find(r => r.f === 'vender_impresa');
  ok(vi && vi.body.p_numero === 1505 && vi.body.p_registro === 'Z7C0012345' && vi.body.p_items[0].producto_id === 1, 'al volver internet sube con vender_impresa()');
  ok((await pg.evaluate(() => Cuadre.leerLocal('cola'))).length === 0, 'y la cola queda vacía');

  // 8. Configuración del dueño: impresora simulada
  await pg.evaluate(() => { closeModal(); go('fiscal'); }); await pg.click('[data-act="medio"]');
  await pg.fill('#mq-ag', 'simulada'); await pg.click('[data-act="mq-cfg"]'); await pg.waitForTimeout(800);
  ok(st.empresa.maquina_agente === 'simulada', 'el dueño cambia el agente (simulada para practicar)');
  await vender();
  await pg.waitForFunction(() => document.getElementById('modal').textContent.includes('900000001'), null, { timeout: 6000 }).catch(() => {});
  const tks = await pg.textContent('#modal');
  ok(tks.includes('900000001') && tks.includes('NO ES UNA FACTURA FISCAL'), 'la impresora simulada numera desde 900000001 y avisa que no es fiscal');
  await pg.evaluate(() => { closeModal(); go('fiscal'); }); await pg.click('[data-act="medio"]');
  await pg.fill('#mq-reg', 'abc'); await pg.click('[data-act="mq-cfg"]'); await pg.waitForTimeout(300);
  ok((await pg.textContent('#toast')).includes('número de registro') && st.empresa.maquina_registro === 'Z7C0012345', 'un registro mal escrito no se guarda');

  ok(errs.length === 0, 'sin errores en la página' + (errs.length ? ': ' + errs.join(' | ').slice(0, 300) : ''));
  await b.close(); process.exit(fallas ? 1 : 0);
})();
