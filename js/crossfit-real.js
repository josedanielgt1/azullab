/* =====================================================================
   Cuadre · CrossFit con datos reales
     * Planes, productos del box y horario de clases: de la base; vacíos
       al instalar. El dueño los arma en «Membresías y pagos».
     * Socios: se cargan de la base y lo que cambia se guarda solo. Un
       socio nuevo queda vencido hasta que se le cobre.
     * Cobro: la base emite la factura (IVA 16 %) y corre el vencimiento.
     * Entrada a clase, reservas, pizarra del día y resultados: se guardan solos.
   Va al final de crossfit.html, después de js/cuadre-comun.js.
   ===================================================================== */
(() => {
  const C = window.Cuadre;
  if (!C || !C.listo || C.crossfit) return;
  const db = C.db, todo = C.todo, esc = C.esc;
  const A = () => C.acceso || {};
  const EMP = () => A().empresa_id;
  const avisar = t => toast(t);
  const p8 = n => String(n).padStart(8, '0');
  const hoyVE = () => new Intl.DateTimeFormat('en-CA', {timeZone: 'America/Caracas'}).format(new Date());
  const ayer = () => addDays(hoyVE(), -1);
  const PLANTILLA = clone(WOD0);
  const sid = id => 'S' + id, dbid = s => s && s._id;
  const g = {soc: new Map(), piz: null};

  /* ---------------- Carga ---------------- */
  async function cargarCatalogo() {
    const [pl, pr, cl] = await Promise.all([
      todo(() => db.from('planes').select('*').eq('empresa_id', EMP()).eq('activo', true).order('precio')),
      todo(() => db.from('productos_box').select('*').eq('empresa_id', EMP()).eq('activo', true).order('nombre')),
      todo(() => db.from('clases').select('*').eq('empresa_id', EMP()).eq('activo', true).order('hora'))]);
    PLANES.length = 0; pl.forEach(r => PLANES.push({id: String(r.id), n: r.nombre, p: +r.precio, d: r.dias, _id: r.id}));
    FX_SYS.PROD.length = 0; pr.forEach(r => FX_SYS.PROD.push({id: String(r.id), n: r.nombre, p: +r.precio, _id: r.id}));
    const res = (CLASES.reduce((m, c) => (m[c.h] = c.res, m), {}));
    CLASES.length = 0; cl.forEach(r => CLASES.push({h: r.hora, coach: r.coach || '', cupo: r.cupo, res: res[r.hora] || [], _id: r.id}));
  }
  const SUYOS = ['id', 'n', 'ci', 'tel', 'plan', 'v', 'nac', 'niv', 'asis', '_id'];
  const socFila = s => { const datos = {}; Object.keys(s).forEach(k => { if (!SUYOS.includes(k)) datos[k] = s[k]; });
    return {cedula: s.ci, nombre: s.n, telefono: s.tel && s.tel !== '—' ? s.tel : null, plan_id: s.plan ? +s.plan || null : null, nacimiento: s.nac || null, nivel: s.niv || null, datos}; };
  async function cargarSocios() {
    const [rs, as] = await Promise.all([
      todo(() => db.from('socios').select('*').eq('empresa_id', EMP()).order('nombre')),
      todo(() => db.from('asistencias').select('socio_id').eq('empresa_id', EMP()))]);
    const cuenta = {}; as.forEach(a => { cuenta[a.socio_id] = (cuenta[a.socio_id] || 0) + 1; });
    SOCIOS.length = 0; g.soc.clear();
    rs.forEach(r => { const s = {emer: '—', les: 'Ninguna', ...(r.datos || {}), id: sid(r.id), n: r.nombre, ci: r.cedula, tel: r.telefono || '—', plan: r.plan_id ? String(r.plan_id) : '',
      v: r.vence || ayer(), nac: r.nacimiento || '', niv: r.nivel || '', asis: cuenta[r.id] || 0, _id: r.id};
      SOCIOS.push(s); g.soc.set(s._id, JSON.stringify(socFila(s))); });
  }
  async function cargarPagos() {
    const desde = new Date(Date.now() - 180 * 864e5).toISOString();
    const rs = await todo(() => db.from('membresias').select('*, documentos(numero, total_usd)').eq('empresa_id', EMP()).gte('creado_en', desde).order('id'));
    PAGOS.length = 0;
    rs.forEach(r => PAGOS.push({f: new Intl.DateTimeFormat('en-CA', {timeZone: 'America/Caracas'}).format(new Date(r.creado_en)), r: r.documentos ? p8(r.documentos.numero) : '',
      s: sid(r.socio_id), plan: String(r.plan_id), usd: +r.precio_usd, tot: r.documentos ? +r.documentos.total_usd : +r.precio_usd, met: r.metodo || '',
      doc: C.docLocal ? C.docLocal(r.documento_id) : null, v0: r.vence_antes, _id: r.id}));
  }
  const firmaPiz = () => JSON.stringify({wod: S.wod, publicada: !!S.pub, reservas: CLASES.reduce((m, c) => (m[c.h] = c.res.map(x => SOCIOS.find(s => s.id === x)).filter(dbid).map(dbid), m), {}),
    resultados: RES.map(r => ({...r, s: (SOCIOS.find(x => x.id === r.s) || {})._id})).filter(r => r.s)});
  async function cargarDia() {
    const hoy = hoyVE();
    const [{data: pz}, as] = await Promise.all([
      db.from('pizarras').select('*').eq('empresa_id', EMP()).eq('fecha', hoy).maybeSingle(),
      todo(() => db.from('asistencias').select('*').eq('empresa_id', EMP()).eq('fecha', hoy).order('id'))]);
    ASIS.length = 0; as.forEach(a => ASIS.push({s: sid(a.socio_id), t: a.hora || '', c: a.clase, _id: a.id}));
    RES.length = 0; MARCAS.length = 0;
    CLASES.forEach(c => { c.res = []; });
    if (pz) {
      S.wod = pz.wod && pz.wod.blocks ? pz.wod : clone(PLANTILLA); S.pub = pz.publicada; S.draft = clone(S.wod); S.dirty = false;
      Object.entries(pz.reservas || {}).forEach(([h, ids]) => { const c = CLASES.find(x => x.h === h); if (c) c.res = ids.map(sid); });
      (pz.resultados || []).forEach(r => RES.push({...r, s: sid(r.s)}));
    } else { S.wod = clone(PLANTILLA); S.draft = clone(PLANTILLA); S.pub = false; S.dirty = false; }
    g.piz = pz ? firmaPiz() : null;
  }

  /* ---------------- Sincronizador ---------------- */
  let enCurso = null, otraVez = false;
  async function sincronizar() {
    if (enCurso) { otraVez = true; return enCurso; }
    enCurso = (async () => { do { otraVez = false; await subir(); } while (otraVez); })()
      .catch(x => avisar('No se pudo guardar: ' + C.msg(x))).finally(() => { enCurso = null; });
    return enCurso;
  }
  async function subir() {
    for (const s of SOCIOS.slice()) {
      const f = socFila(s), j = JSON.stringify(f);
      if (s._id && g.soc.get(s._id) === j) continue;
      if (s._id) { const {error} = await db.from('socios').update(f).eq('id', s._id); if (error) throw error; g.soc.set(s._id, j); continue; }
      const viejo = s.id, {data, error} = await db.from('socios').insert({...f, vence: s.v, empresa_id: EMP()}).select().single();
      if (error) { const i = SOCIOS.indexOf(s); if (i >= 0) SOCIOS.splice(i, 1); render(); throw /duplicate|unique/i.test(error.message) ? new Error('Esa cédula ya está registrada') : error; }
      s._id = data.id; s.id = sid(data.id); g.soc.set(s._id, j);
      CLASES.forEach(c => { c.res = c.res.map(x => x === viejo ? s.id : x); });
      ASIS.forEach(a => { if (a.s === viejo) a.s = s.id; }); RES.forEach(r => { if (r.s === viejo) r.s = s.id; });
      if (S.pay && S.pay.s === viejo) S.pay.s = s.id;
    }
    for (const a of ASIS) {
      if (a._id) continue;
      const so = SOCIOS.find(x => x.id === a.s); if (!so || !so._id) continue;
      const {data, error} = await db.from('asistencias').insert({empresa_id: EMP(), socio_id: so._id, fecha: hoyVE(), clase: a.c, hora: a.t || null}).select().single();
      if (error && !/duplicate/i.test(error.message)) throw error;
      a._id = data ? data.id : -1;
    }
    const j = firmaPiz();
    if (j !== g.piz) {
      const {error} = await db.from('pizarras').upsert({empresa_id: EMP(), fecha: hoyVE(), ...JSON.parse(j), actualizado: new Date().toISOString()}, {onConflict: 'empresa_id,fecha'});
      if (error) throw error; g.piz = j;
    }
  }
  const tras = () => setTimeout(() => { if (A().tipo === 'crossfit' && S.view !== 'login') sincronizar(); }, 0);
  ['click', 'submit', 'change'].forEach(ev => document.addEventListener(ev, tras));

  /* ---------------- Cobro: la base factura y corre el vencimiento ---------------- */
  let pase = false, cobro = null;
  const fxEmitir = FX.emitir;
  FX.emitir = o => {
    const d = fxEmitir(o);
    if (cobro && o.origen && o.origen.pago) { const doc = cobro.documento; d.num = p8(doc.numero); d.ctrl = doc.numero_control || 'Pendiente de imprenta'; d.dbId = doc.id; d.cont = false; FX.n.FAC = doc.numero + 1; }
    return d;
  };
  document.addEventListener('click', async e => {
    const b = e.target.closest('[data-act="pagar"]'); if (!b || A().tipo !== 'crossfit') return;
    if (pase) { pase = false; return; }
    e.preventDefault(); e.stopImmediatePropagation();
    if (!navigator.onLine) { avisar('Sin internet no se puede facturar todavía'); return; }
    const txt = b.innerHTML; b.disabled = true; b.textContent = 'Cobrando…';
    try {
      await sincronizar();
      const s = socBy(S.pay.s), pl = planBy(S.pay.plan);
      if (!s || !s._id) throw new Error('Escoge el socio');
      if (!pl) throw new Error('Escoge el plan (si no hay, créalo en Membresías y pagos)');
      const {data: tasa} = await db.rpc('tasa_del_dia');
      if (tasa && Math.abs(+tasa - RATE) >= 0.005) { RATE = +tasa; openModal(payModal()); avisar(`La tasa BCV cambió a ${nf(RATE)}: revisa el cobro`); return; }
      const pr = FX_SYS.PROD.find(x => x.id === S.pay.prod);
      const {data, error} = await db.rpc('cobrar_membresia', {p_empresa: EMP(), p_socio: s._id, p_plan: pl._id, p_metodo: S.pay.met,
        p_divisa: ['Efectivo $', 'Zelle'].includes(S.pay.met), p_producto: pr ? {id: pr._id, cantidad: S.pay.pq || 1} : null});
      if (error) throw error;
      cobro = data; b.disabled = false; b.innerHTML = txt; pase = true; b.click();
      s.v = data.socio.vence; s.plan = String(data.socio.plan_id);
      const pg = PAGOS[PAGOS.length - 1]; if (pg && pg.s === s.id) { pg._id = data.membresia.id; pg.f = hoyVE(); }
      cobro = null; render(); if (document.querySelector('#modal:not([hidden])')) openModal(payModal({doc: FX.docs[FX.docs.length - 1].id}));
    } catch (x) { cobro = null; avisar(C.msg(x)); }
    finally { if (b.isConnected && b.textContent === 'Cobrando…') { b.disabled = false; b.innerHTML = txt; } }
  }, true);

  /* ---------------- Planes, productos y horario (dueño) ---------------- */
  const TIPOS = {
    plan: {tabla: 'planes', titulo: 'Plan', lista: () => PLANES, campos: [['n', 'nombre', 'Nombre', 'text'], ['p', 'precio', 'Precio en $ (sin IVA)', 'num'], ['d', 'dias', 'Días que dura', 'int']]},
    prod: {tabla: 'productos_box', titulo: 'Producto', lista: () => FX_SYS.PROD, campos: [['n', 'nombre', 'Nombre', 'text'], ['p', 'precio', 'Precio en $ (sin IVA)', 'num']]},
    clase: {tabla: 'clases', titulo: 'Clase', lista: () => CLASES, campos: [['h', 'hora', 'Hora (HH:MM)', 'text'], ['coach', 'coach', 'Coach', 'text'], ['cupo', 'cupo', 'Cupo', 'int']]}
  };
  const puedeArmar = () => ['dueno', 'gerente'].includes(A().rol);
  const fila = (t, x, i) => `<div class="it"><div class="t"><b>${esc(t === 'clase' ? x.h : x.n)}</b><span class="small muted">${t === 'plan' ? `$ ${nf(x.p)} + IVA · ${x.d} días` : t === 'prod' ? `$ ${nf(x.p)} + IVA` : `${esc(x.coach || 'Sin coach')} · cupo ${x.cupo}`}</span></div>
    <button class="btn sm" data-act="cfx-edit" data-t="${t}" data-i="${i}">${ic('edit')}Editar</button></div>`;
  const panel = () => !puedeArmar() ? '' : `<section class="panel"><div class="hd"><h2>Planes, productos y horario</h2><span class="muted small">Lo que se cobra y cuándo hay clase</span></div>
    <div class="grid g3" style="gap:0;align-items:start">${Object.entries(TIPOS).map(([t, T]) => `<div class="bd" style="display:grid;gap:8px;align-content:start">
      <div class="row"><b>${t === 'plan' ? 'Planes' : t === 'prod' ? 'Productos' : 'Horario'}</b><span class="spacer"></span><button class="btn sm" data-act="cfx-edit" data-t="${t}">${ic('plus')}Agregar</button></div>
      <div class="list">${T.lista().map((x, i) => fila(t, x, i)).join('') || '<p class="small muted" style="margin:0">Todavía no hay.</p>'}</div></div>`).join('')}</div></section>`;
  const vPagos = V.pagos;
  V.pagos = () => panel() + (PLANES.length ? vPagos() : '<p class="lead">Crea al menos un plan para empezar a cobrar membresías.</p>');
  const modal = (t, i) => { const T = TIPOS[t], x = i == null ? null : T.lista()[i];
    return `<div class="sheet" role="dialog" aria-modal="true" style="max-width:460px"><div class="hd"><h2>${x ? 'Editar' : 'Nuevo'}: ${T.titulo.toLowerCase()}</h2><button class="x" data-act="close" aria-label="Cerrar">${ic('x')}</button></div>
    <form class="bd" id="cfx-f" data-t="${t}" data-i="${i == null ? '' : i}" style="display:grid;gap:10px">
      ${T.campos.map(([k, , l, tipo]) => `<div class="field"><label for="cfx-${k}">${l}</label><input id="cfx-${k}" class="input ${tipo !== 'text' ? 'num' : ''}" ${tipo !== 'text' ? 'inputmode="decimal"' : ''} value="${x ? esc(tipo === 'num' ? nf(x[k]) : x[k]) : ''}" required></div>`).join('')}
      <div class="row">${x ? `<button type="button" class="btn" data-act="cfx-quitar" data-t="${t}" data-i="${i}">Quitar</button>` : ''}<span class="spacer"></span><button class="btn primary" type="submit">${ic('check')}Guardar</button></div></form></div>`; };
  const num = v => parseFloat(String(v).replace(/\./g, '').replace(',', '.'));
  document.addEventListener('click', async e => {
    const b = e.target.closest('[data-act="cfx-edit"],[data-act="cfx-quitar"]'); if (!b) return;
    e.stopImmediatePropagation();
    if (b.dataset.act === 'cfx-edit') { openModal(modal(b.dataset.t, b.dataset.i === undefined ? null : +b.dataset.i)); return; }
    const T = TIPOS[b.dataset.t], x = T.lista()[+b.dataset.i];
    const {error} = await db.from(T.tabla).update({activo: false}).eq('id', x._id);
    if (error) { avisar(C.msg(error)); return; }
    await cargarCatalogo(); closeModal(); render(); avisar('Quitado: lo ya cobrado no cambia');
  }, true);
  document.addEventListener('submit', async e => {
    if (e.target.id !== 'cfx-f') return;
    e.preventDefault(); e.stopImmediatePropagation();
    const t = e.target.dataset.t, T = TIPOS[t], i = e.target.dataset.i, x = i === '' ? null : T.lista()[+i], f = {};
    for (const [k, col, l, tipo] of T.campos) {
      const v = document.getElementById('cfx-' + k).value.trim();
      f[col] = tipo === 'text' ? v : tipo === 'int' ? parseInt(v) : num(v);
      if (tipo !== 'text' && !(f[col] >= (col === 'dias' || col === 'cupo' ? 1 : 0))) { avisar('Revisa: ' + l); return; }
      if (tipo === 'text' && col !== 'coach' && !v) { avisar('Falta: ' + l); return; }
    }
    if (t === 'clase' && !/^\d{2}:\d{2}$/.test(f.hora)) { avisar('Escribe la hora así: 06:00'); return; }
    const q = x ? db.from(T.tabla).update(f).eq('id', x._id) : db.from(T.tabla).insert({...f, empresa_id: EMP()});
    const {error} = await q;
    if (error) { avisar(/duplicate/i.test(error.message) ? 'Ya hay una clase a esa hora' : C.msg(error)); return; }
    await cargarCatalogo(); closeModal(); render(); avisar('Guardado');
  }, true);

  C.crossfit = {sincronizar};

  /* ---------------- Al entrar ---------------- */
  C.alEntrar(async a => {
    if (a.tipo !== 'crossfit') return;
    await cargarCatalogo();
    await cargarSocios();
    await cargarPagos();
    await cargarDia();
    if (S.pay) { S.pay.s = SOCIOS[0] ? SOCIOS[0].id : ''; S.pay.plan = PLANES[0] ? PLANES[0].id : ''; S.pay.prod = ''; }
    S.me = SOCIOS[0] ? SOCIOS[0].id : null;
  });
})();
