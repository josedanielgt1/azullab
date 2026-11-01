/* =====================================================================
   Cuadre · Laboratorio con datos reales
     * Catálogo de exámenes y perfiles: de la base. En una instalación
       nueva está vacío y el dueño puede cargar el catálogo base para
       ajustarlo (precios y valores de referencia).
     * Pacientes y médicos: se cargan de la base y lo que cambia se guarda solo.
     * Orden nueva: la base crea la orden y su factura juntas (crear_orden).
     * Toma, resultados, validación y entrega: se guardan solos; la base
       no deja validar a quien no es bioanalista ni cambiar un resultado validado.
   Va al final de laboratorio.html, después de js/cuadre-comun.js.
   ===================================================================== */
(() => {
  const C = window.Cuadre;
  if (!C || !C.listo || C.laboratorio) return;
  const db = C.db, todo = C.todo;
  const A = () => C.acceso || {};
  const EMP = () => A().empresa_id;
  const avisar = t => toast(t);
  const r2 = n => Math.round(n * 100) / 100;
  const p8 = n => String(n).padStart(8, '0');
  const hm = f => new Date(f).toLocaleTimeString('es-VE', {hour: '2-digit', minute: '2-digit', hour12: false, timeZone: 'America/Caracas'});
  const SIN_MEDICO = MEDICOS[0];
  // El catálogo de la maqueta queda como «catálogo base» que el dueño puede cargar
  const BASE = {ex: JSON.parse(JSON.stringify(EX)), perf: JSON.parse(JSON.stringify(PERF))};

  /* ---------------- Catálogo ---------------- */
  const exFila = e => ({codigo: e.c, nombre: e.n, area: e.a || null, tubo: e.t || null, tiempo: e.h || null, precio: r2(+e.p || 0), parametros: e.ps || []});
  const deEx = r => ({c: r.codigo, n: r.nombre, a: r.area || 'Otros', t: r.tubo || '', h: r.tiempo || '', p: +r.precio, ps: r.parametros || [], _id: r.id});
  const pfFila = p => ({codigo: p.c, nombre: p.n, examenes: p.ex || [], precio: r2(+p.p || 0)});
  const dePf = r => ({c: r.codigo, n: r.nombre, ex: r.examenes || [], p: +r.precio, _id: r.id});
  const g = {ex: new Map(), perf: new Map(), pac: new Map(), ord: new Map(), med: new Set()};
  const refrescarAreas = () => { if (typeof AREAS === 'object') { AREAS.length = 0; AREAS.push('Todas', ...new Set(EX.map(e => e.a))); } };

  async function cargarCatalogo() {
    const [ex, pf] = await Promise.all([
      todo(() => db.from('examenes').select('*').eq('empresa_id', EMP()).eq('activo', true).order('id')),
      todo(() => db.from('perfiles_lab').select('*').eq('empresa_id', EMP()).eq('activo', true).order('id'))]);
    EX.length = 0; PERF.length = 0; g.ex.clear(); g.perf.clear();
    ex.forEach(r => { const e = deEx(r); EX.push(e); g.ex.set(e.c, JSON.stringify(exFila(e))); });
    pf.forEach(r => { const p = dePf(r); PERF.push(p); g.perf.set(p.c, JSON.stringify(pfFila(p))); });
    refrescarAreas();
  }
  async function cargarBase() {
    const {error: e1} = await db.from('examenes').insert(BASE.ex.map(e => ({...exFila(e), empresa_id: EMP()})));
    if (e1) throw e1;
    const {error: e2} = await db.from('perfiles_lab').insert(BASE.perf.map(p => ({...pfFila(p), empresa_id: EMP()})));
    if (e2) throw e2;
    await cargarCatalogo();
  }
  const vCatalogo = V.catalogo;
  V.catalogo = () => {
    if (EX.length || PERF.length) return vCatalogo();
    const puede = ['dueno', 'gerente'].includes(A().rol);
    return `<section class="panel"><div class="hd"><h2>El catálogo está vacío</h2></div><div class="bd" style="display:grid;gap:12px">
      <p style="margin:0">Para crear órdenes hacen falta los exámenes con su tubo, su precio y sus valores de referencia.</p>
      ${puede ? `<p class="small muted" style="margin:0">Puedes cargar el catálogo base (${BASE.ex.length} exámenes y ${BASE.perf.length} perfiles) y luego ajustar precios y valores de referencia con el bioanalista.</p>
        <button class="btn primary" data-act="lab-base" style="justify-self:start">${ic('plus')}Cargar el catálogo base</button>`
        : '<p class="small muted" style="margin:0">Pídele al dueño que cargue el catálogo.</p>'}</div></section>`;
  };
  document.addEventListener('click', async e => {
    const b = e.target.closest('[data-act="lab-base"]'); if (!b) return;
    e.stopImmediatePropagation(); b.disabled = true;
    try { await cargarBase(); render(); avisar('Catálogo base cargado: revisa precios y valores de referencia'); }
    catch (x) { b.disabled = false; avisar(C.msg(x)); }
  }, true);

  /* ---------------- Médicos ---------------- */
  async function cargarMedicos() {
    const rs = await todo(() => db.from('medicos').select('nombre').eq('empresa_id', EMP()).eq('activo', true).order('nombre'));
    MEDICOS.length = 0; MEDICOS.push(SIN_MEDICO, ...rs.map(r => r.nombre)); g.med = new Set(rs.map(r => r.nombre));
  }
  const medIdx = nombre => { if (!nombre) return 0; let i = MEDICOS.indexOf(nombre); if (i < 0) { MEDICOS.push(nombre); i = MEDICOS.length - 1; } return i; };

  /* ---------------- Pacientes ---------------- */
  const SUYOS = ['id', 'ci', 'n', 's', 'b', 'tel', '_id'];
  const pacFila = p => { const datos = {}; Object.keys(p).forEach(k => { if (!SUYOS.includes(k)) datos[k] = p[k]; });
    return {cedula: p.ci && p.ci !== '—' ? p.ci : null, nombre: p.n, sexo: ['M', 'F'].includes(p.s) ? p.s : null, nacimiento: p.b || null, telefono: p.tel && p.tel !== '—' ? p.tel : null, datos}; };
  // Los campos de la ficha completa, para los pacientes que se registraron con lo mínimo
  const normPac = p => { const w = String(p.n || '').split(' ');
    const def = {nom: w.slice(0, -1).join(' '), ape: w[w.length - 1], tel2: '', mail: '', dir: '', sector: '', mun: 'Andrés Bello', ocup: '', sangre: 'No sabe',
                 ant: [], meds: '', alerg: '', emer: null, rep: null, seg: 'Particular', orig: '', alta: HOY};
    Object.keys(def).forEach(k => { if (p[k] === undefined) p[k] = def[k]; }); return p; };
  const dePac = r => normPac({...(r.datos || {}), id: 'P' + r.id, ci: r.cedula || '', n: r.nombre, s: r.sexo || '', b: r.nacimiento || '', tel: r.telefono || '—', _id: r.id});
  async function cargarPacientes() {
    const rs = await todo(() => db.from('pacientes').select('*').eq('empresa_id', EMP()).order('id'));
    PATS.length = 0; g.pac.clear();
    rs.forEach(r => { const p = dePac(r); PATS.push(p); g.pac.set(p._id, JSON.stringify(pacFila(p))); });
  }

  /* ---------------- Órdenes ---------------- */
  const FIJOS = ['n', 'pat', 'items', 'usd', 'fac', 'ctrl', 'cont', 'doc', 't', 'med', 'urg', 'vis', 'st', '_id', 'fecha', 'fechaIso'];
  const ordDatos = o => { const d = {}; Object.keys(o).forEach(k => { if (!FIJOS.includes(k)) d[k] = o[k]; }); return d; };
  const ordFirma = o => JSON.stringify({estado: o.st, datos: ordDatos(o)});
  async function cargarOrdenes() {
    const desde = new Date(Date.now() - 120 * 864e5).toISOString();
    const [rs, {data: per}] = await Promise.all([
      todo(() => db.from('ordenes').select('*, documentos(numero, numero_control, origen)').eq('empresa_id', EMP()).gte('creado_en', desde).order('id')),
      db.from('perfiles').select('user_id,nombre')]);
    const nombres = {}; (per || []).forEach(p => { nombres[p.user_id] = p.nombre; });
    ORD.length = 0; g.ord.clear();
    rs.forEach(r => {
      const d = r.documentos || {};
      const o = {by: nombres[r.creado_por] || '', res: {}, ...(r.datos || {}), n: r.numero, pat: 'P' + r.paciente_id, items: (r.items || []).map(i => ({k: i.k, c: i.c})),
        st: r.estado, t: hm(r.creado_en), med: medIdx(r.medico), urg: r.urgente, vis: r.visita || {}, usd: +r.total_usd,
        fac: d.numero ? (d.origen === 'contingencia' ? 'C-' : '') + p8(d.numero) : '', ctrl: d.numero_control || 'Pendiente de imprenta', cont: d.origen === 'contingencia',
        doc: C.docLocal ? C.docLocal(r.documento_id) : null, _id: r.id,
        fechaIso: r.creado_en, fecha: new Intl.DateTimeFormat('es-VE', {day: '2-digit', month: '2-digit', year: 'numeric', timeZone: 'America/Caracas'}).format(new Date(r.creado_en)).replace(/\//g, '-')};
      ORD.push(o); g.ord.set(o._id, ordFirma(o));
    });
  }

  /* ---------------- Sincronizador ---------------- */
  let enCurso = null, otraVez = false;
  async function sincronizar() {
    if (enCurso) { otraVez = true; return enCurso; }
    enCurso = (async () => { do { otraVez = false; await subir(); await subirReactivos(); } while (otraVez); })()
      .catch(async x => { avisar('No se pudo guardar: ' + C.msg(x)); await cargarOrdenes().catch(() => {}); render(); })
      .finally(() => { enCurso = null; });
    return enCurso;
  }
  async function subir() {
    for (const m of MEDICOS.slice(1)) {
      if (g.med.has(m)) continue;
      const {error} = await db.from('medicos').upsert({empresa_id: EMP(), nombre: m}, {onConflict: 'empresa_id,nombre', ignoreDuplicates: true});
      if (error) throw error; g.med.add(m);
    }
    for (const p of PATS.slice()) {
      normPac(p);
      const f = pacFila(p), j = JSON.stringify(f);
      if (p._id && g.pac.get(p._id) === j) continue;
      if (p._id) { const {error} = await db.from('pacientes').update(f).eq('id', p._id); if (error) throw error; g.pac.set(p._id, j); continue; }
      const viejo = p.id, {data, error} = await db.from('pacientes').insert({...f, empresa_id: EMP()}).select().single();
      if (error) { const i = PATS.indexOf(p); if (i >= 0) PATS.splice(i, 1); if (S.ord && S.ord.pat === viejo) S.ord.pat = null; render();
        throw /duplicate|unique/i.test(error.message) ? new Error('Ya hay un paciente con esa cédula') : error; }
      p._id = data.id; p.id = 'P' + data.id; g.pac.set(p._id, j);
      if (S.ord && S.ord.pat === viejo) S.ord.pat = p.id;
      ORD.forEach(o => { if (o.pat === viejo) o.pat = p.id; });
    }
    for (const e of EX) { const j = JSON.stringify(exFila(e)); if (g.ex.get(e.c) === j) continue;
      const q = e._id ? db.from('examenes').update(exFila(e)).eq('id', e._id) : db.from('examenes').insert({...exFila(e), empresa_id: EMP()});
      const {data, error} = await q.select().single(); if (error) throw error; e._id = data.id; g.ex.set(e.c, j); }
    for (const p of PERF) { const j = JSON.stringify(pfFila(p)); if (g.perf.get(p.c) === j) continue;
      const q = p._id ? db.from('perfiles_lab').update(pfFila(p)).eq('id', p._id) : db.from('perfiles_lab').insert({...pfFila(p), empresa_id: EMP()});
      const {data, error} = await q.select().single(); if (error) throw error; p._id = data.id; g.perf.set(p.c, j); }
    for (const o of ORD) {
      if (!o._id) continue;
      const j = ordFirma(o); if (g.ord.get(o._id) === j) continue;
      const {data, error} = await db.from('ordenes').update({estado: o.st, datos: ordDatos(o)}).eq('id', o._id).select('id');
      if (error) throw error;
      if (!data.length) throw new Error('Tu usuario no puede cambiar esa orden');
      g.ord.set(o._id, j);
    }
  }
  const tras = () => setTimeout(() => { if (A().tipo === 'laboratorio' && S.view !== 'login') sincronizar(); }, 0);
  ['click', 'submit', 'change'].forEach(ev => document.addEventListener(ev, tras));

  /* ---------------- Orden nueva: la base la crea con su factura ---------------- */
  let pase = false, ordenReal = null;
  const nextNOriginal = nextN;
  nextN = () => ordenReal ? ordenReal.orden.numero : nextNOriginal();
  const fxEmitir = FX.emitir;
  FX.emitir = o => {
    const d = fxEmitir(o);
    if (ordenReal && o.origen && o.origen.ord) { const doc = ordenReal.documento; d.num = p8(doc.numero); d.ctrl = doc.numero_control || 'Pendiente de imprenta'; d.dbId = doc.id; d.cont = false; FX.n.FAC = doc.numero + 1; }
    return d;
  };
  document.addEventListener('click', async e => {
    const b = e.target.closest('[data-act="emit"]'); if (!b || A().tipo !== 'laboratorio') return;
    if (pase) { pase = false; return; }
    e.preventDefault(); e.stopImmediatePropagation();
    if (!navigator.onLine) { avisar('Sin internet no se puede facturar todavía: el modo sin conexión viene en una próxima versión'); return; }
    if (!S.pay) { avisar('Escoge la forma de pago'); return; }
    const txt = b.innerHTML; b.disabled = true; b.textContent = 'Creando la orden…';
    try {
      await sincronizar();   // el paciente nuevo necesita su número de la base
      const pt = patBy(S.ord.pat); if (!pt || !pt._id) throw new Error('Guarda primero al paciente');
      const {data: tasa} = await db.rpc('tasa_del_dia');
      if (tasa && Math.abs(+tasa - S.rate) >= 0.005) { S.rate = +tasa; openModal(payModal()); avisar(`La tasa BCV cambió a ${nf(S.rate)}: revisa el cobro`); return; }
      const usdT = ordTotal(), div = ['Efectivo USD', 'Zelle'].includes(S.pay);
      const {data, error} = await db.rpc('crear_orden', {p_empresa: EMP(), p_paciente: pt._id, p_items: S.ord.items.map(i => ({k: i.k, c: i.c})),
        p_medico: +S.ord.med ? MEDICOS[+S.ord.med] : null, p_urgente: !!S.ord.urg, p_visita: S.ord.vis || {},
        p_pagos: [{metodo: S.pay, monto_bs: r2(usdT * S.rate), divisa: div}]});
      if (error) throw error;
      ordenReal = data; b.disabled = false; b.innerHTML = txt; pase = true; b.click();
      const o = ORD.find(x => x.n === data.orden.numero);
      if (o) { o._id = data.orden.id; g.ord.set(o._id, JSON.stringify({estado: data.orden.estado, datos: {}})); }
      ordenReal = null; sincronizar();   // guarda quién la creó y cómo pagó
    } catch (x) { ordenReal = null; avisar(C.msg(x)); }
    finally { if (b.isConnected && b.textContent === 'Creando la orden…') { b.disabled = false; b.innerHTML = txt; } }
  }, true);

  /* ---------------- Reactivos e insumos ---------------- */
  let reacGuardado = '[]';
  async function cargarReactivos() {
    const {data} = await db.from('colecciones').select('datos').eq('empresa_id', EMP()).eq('nombre', 'equipo_reactivos').maybeSingle();
    REAC.length = 0; if (data && Array.isArray(data.datos)) REAC.push(...data.datos);
    reacGuardado = JSON.stringify(REAC);
  }
  async function subirReactivos() {
    const j = JSON.stringify(REAC); if (j === reacGuardado) return;
    const {error} = await db.from('colecciones').upsert({empresa_id: EMP(), nombre: 'equipo_reactivos', datos: REAC, actualizado: new Date().toISOString()}, {onConflict: 'empresa_id,nombre'});
    if (error) throw error; reacGuardado = j;
  }
  const num = v => parseFloat(String(v || '').replace(/\./g, '').replace(',', '.'));
  const reacModal = i => { const r = i == null ? null : REAC[i], v = k => r ? C.esc(r[k]) : '';
    return `<div class="sheet" role="dialog" aria-modal="true" style="max-width:520px"><div class="hd"><h2>${r ? 'Corregir ' + C.esc(r.n) : 'Entrada de reactivo o insumo'}</h2><button class="x" data-act="close" aria-label="Cerrar">${ic('x')}</button></div>
    <form class="bd" id="lab-reac-f" data-i="${i == null ? '' : i}" style="display:grid;gap:10px">
      <div class="field"><label for="rq-n">Nombre</label><input id="rq-n" class="input" value="${v('n')}" required></div>
      <div class="grid g2" style="gap:10px"><div class="field"><label for="rq-a">Área</label><input id="rq-a" class="input" value="${v('a') || 'Química'}"></div>
        <div class="field"><label for="rq-l">Lote</label><input id="rq-l" class="input num" value="${v('l')}" required></div></div>
      <div class="grid g2" style="gap:10px"><div class="field"><label for="rq-e">Vence</label><input id="rq-e" class="input" type="date" value="${v('e')}" required></div>
        <div class="field"><label for="rq-q">Cantidad${r ? ' que hay' : ' que entra'}</label><input id="rq-q" class="input num" inputmode="decimal" value="${r ? String(r.q).replace('.', ',') : ''}" required></div></div>
      <div class="grid g2" style="gap:10px"><div class="field"><label for="rq-u">Unidad</label><input id="rq-u" class="input" value="${v('u') || 'pruebas'}"></div>
        <div class="field"><label for="rq-d">Se gastan por día</label><input id="rq-d" class="input num" inputmode="decimal" value="${r ? String(r.d).replace('.', ',') : ''}" required></div></div>
      <button class="btn primary big" type="submit">${ic('check')}Guardar</button></form></div>`; };
  document.addEventListener('click', e => {
    const b = e.target.closest('[data-act="lab-reac"]'); if (!b) return;
    e.stopImmediatePropagation(); openModal(reacModal(b.dataset.i === undefined ? null : +b.dataset.i));
  }, true);
  document.addEventListener('submit', e => {
    if (e.target.id !== 'lab-reac-f') return;
    e.preventDefault(); e.stopImmediatePropagation();
    const g = id => document.getElementById(id).value.trim();
    const x = {n: g('rq-n'), a: g('rq-a') || 'Química', l: g('rq-l').toUpperCase(), e: g('rq-e'), q: num(g('rq-q')), u: g('rq-u') || 'pruebas', d: num(g('rq-d'))};
    if (!x.n || !x.l || !x.e || !(x.q >= 0) || !(x.d > 0)) { avisar('Completa nombre, lote, vencimiento, cantidad y consumo por día'); return; }
    const i = e.target.dataset.i;
    if (i !== '') REAC[+i] = x;
    else { const y = REAC.find(r => r.n === x.n && r.l === x.l); if (y) { y.q = +(y.q + x.q).toFixed(3); y.e = x.e; y.d = x.d; } else REAC.push(x); }
    closeModal(); render(); avisar(i !== '' ? 'Existencia corregida' : 'Entrada registrada');
  }, true);

  /* ---------------- Historial de resultados de cada paciente ---------------- */
  function armarHistorial() {
    Object.keys(HIST).forEach(k => delete HIST[k]);
    const hoy = new Intl.DateTimeFormat('es-VE', {day: '2-digit', month: '2-digit', year: 'numeric', timeZone: 'America/Caracas'}).format(new Date()).replace(/\//g, '-');
    ORD.filter(o => ['Validado', 'Entregado'].includes(o.st) && o.fecha && o.fecha !== hoy)
      .sort((a, b) => a.fechaIso.localeCompare(b.fechaIso))
      .forEach(o => Object.entries(o.res || {}).forEach(([k, v]) => { const n = +v; if (!isFinite(n) || v === '') return;
        const h = HIST[o.pat] = HIST[o.pat] || {}; (h[k] = h[k] || []).push([o.fecha, n]); }));
  }

  C.laboratorio = {sincronizar, cargarOrdenes};

  /* ---------------- Al entrar ---------------- */
  C.alEntrar(async a => {
    if (a.tipo !== 'laboratorio') return;
    await cargarCatalogo();
    await cargarMedicos();
    await cargarPacientes();
    await cargarOrdenes();
    await cargarReactivos().catch(x => console.error('Cuadre laboratorio: reactivos', x));
    armarHistorial();
    if (S.ord && typeof newOrd === 'function') S.ord = newOrd();
    S.queue.length = 0;
  });
})();
