/* =====================================================================
   Cuadre · Farmacia con datos reales
     * Catálogo: al entrar se carga de la base (vacío en una instalación
       nueva). Lo que se crea o cambia en pantalla se guarda solo.
     * Clientes: igual que el catálogo.
     * Existencia: solo la cambian vender(), recibir_compra() y
       salida_inventario() en la base. Aquí se refleja lo que respondió.
     * Venta: la factura la emite la base (número correlativo del RIF);
       el ticket sale con ese número.
     * Facturas del mes y ventas de hoy: se leen de la base.
   Va al final de farmacia.html, después de js/cuadre-comun.js.
   ===================================================================== */
(() => {
  const C = window.Cuadre;
  if (!C || !C.listo) return;
  const db = C.db;
  const A = () => C.acceso || {};
  const EMP = () => A().empresa_id;
  const avisar = t => toast(t);
  const r2 = n => Math.round(n * 100) / 100;
  const p8 = n => String(n).padStart(8, '0');
  const hoyVE = () => new Intl.DateTimeFormat('en-CA', {timeZone: 'America/Caracas'}).format(new Date());
  const dmy = iso => iso.slice(8, 10) + '/' + iso.slice(5, 7) + '/' + iso.slice(0, 4);

  /* Lee todas las filas, de 1000 en 1000 (límite de Supabase por consulta) */
  async function todo(armar) {
    const out = [];
    for (let i = 0; ; i += 1000) {
      const {data, error} = await armar().range(i, i + 999);
      if (error) throw error;
      out.push(...data);
      if (data.length < 1000) return out;
    }
  }

  /* ---------------- Producto: base ↔ pantalla ---------------- */
  const lote = l => ({id: l.id, l: l.lote, e: l.vence, q: +l.cantidad, c: +l.costo, ...(l.precio != null ? {pv: +l.precio} : {})});
  const deFila = (r, ls) => {
    const lots = (ls || []).filter(l => +l.cantidad > 0).map(lote);
    return {id: r.id, code: r.codigo || '—', alt: r.codigos_alt || [], name: r.nombre, act: r.principio_activo || '—', lab: r.laboratorio || '—',
      pres: r.presentacion || '—', cat: r.seccion || 'Otros', iva: r.iva, cost: +r.costo, margen: +r.margen, price: +r.precio,
      pmvp: r.pmvp == null ? null : +r.pmvp, porLote: r.por_lote, min: r.minimo, rx: r.rx, ctrl: r.controlado, hist: r.historial || [],
      stock: lots.reduce((t, l) => t + l.q, 0), lots};
  };
  const aFila = p => ({codigo: p.code === '—' ? null : p.code, codigos_alt: p.alt || [], nombre: p.name, principio_activo: p.act,
    laboratorio: p.lab, presentacion: p.pres, seccion: p.cat, iva: p.iva, costo: Math.round((p.cost || 0) * 10000) / 10000, margen: p.margen ?? 30,
    precio: r2(p.price) || 0, pmvp: p.pmvp || null, por_lote: !!p.porLote, minimo: p.min ?? 5, rx: !!p.rx, controlado: !!p.ctrl,
    historial: p.hist || []});

  /* Lo último que quedó guardado, para subir solo lo que cambia */
  const guardado = new Map();      // id → JSON de aFila
  const lotesGuardados = new Map(); // id del lote → "costo|precio"
  const marcar = p => { guardado.set(p.id, JSON.stringify(aFila(p))); (p.lots || []).forEach(l => { if (l.id) lotesGuardados.set(l.id, `${l.c}|${l.pv ?? ''}`); }); };

  async function cargarCatalogo() {
    const [ps, ls] = await Promise.all([
      todo(() => db.from('productos').select('*').eq('empresa_id', EMP()).eq('activo', true).order('id')),
      todo(() => db.from('lotes').select('*').eq('empresa_id', EMP()).gt('cantidad', 0).order('vence'))]);
    const por = {}; ls.forEach(l => (por[l.producto_id] = por[l.producto_id] || []).push(l));
    P.length = 0; guardado.clear(); lotesGuardados.clear();
    ps.forEach(r => { const p = deFila(r, por[r.id]); P.push(p); marcar(p); });
  }
  async function recargar(ids) {
    ids = [...new Set(ids)].filter(id => guardado.has(id)); if (!ids.length) return;
    const [{data: ps}, {data: ls}] = await Promise.all([db.from('productos').select('*').in('id', ids), db.from('lotes').select('*').in('producto_id', ids).gt('cantidad', 0).order('vence')]);
    (ps || []).forEach(r => {
      const nuevo = deFila(r, (ls || []).filter(l => l.producto_id === r.id)), i = P.findIndex(x => x.id === r.id);
      if (i >= 0) Object.assign(P[i], nuevo); else P.push(nuevo);
      marcar(i >= 0 ? P[i] : nuevo);
    });
  }

  /* ---------------- Sincronizador del catálogo y los clientes ---------------- */
  let enCurso = null, otraVez = false;
  async function sincronizar() {
    if (enCurso) { otraVez = true; return enCurso; }
    enCurso = (async () => {
      do { otraVez = false; await subirCatalogo(); await subirClientes(); } while (otraVez);
    })().catch(x => avisar('No se pudo guardar: ' + C.msg(x))).finally(() => { enCurso = null; });
    return enCurso;
  }
  async function subirCatalogo() {
    const vivos = new Set();
    for (const p of P.slice()) {
      if (guardado.has(p.id)) {
        vivos.add(p.id);
        const f = aFila(p), j = JSON.stringify(f);
        if (j !== guardado.get(p.id)) {
          const {error} = await db.from('productos').update(f).eq('id', p.id);
          if (error) { await recargar([p.id]); render(); throw error; }
          guardado.set(p.id, j);
        }
        for (const l of p.lots || []) {
          if (!l.id) continue;
          const k = `${l.c}|${l.pv ?? ''}`;
          if (lotesGuardados.get(l.id) !== k) {
            const {error} = await db.from('lotes').update({costo: l.c ?? 0, precio: l.pv ?? null}).eq('id', l.id);
            if (error) throw error;
            lotesGuardados.set(l.id, k);
          }
        }
      } else {
        // Producto nuevo: la base le da su número y se cambia en todas partes
        const viejo = p.id, {data, error} = await db.from('productos').insert({...aFila(p), empresa_id: EMP()}).select().single();
        if (error) { const i = P.indexOf(p); if (i >= 0) P.splice(i, 1); render(); throw error; }
        p.id = data.id; marcar(p); vivos.add(p.id);
        RECV.forEach(r => { if (r.id === viejo) r.id = p.id; });
        S.cart.forEach(c => { if (c.id === viejo) c.id = p.id; });
      }
    }
    // Lo que salió del catálogo (por ejemplo al unir duplicados) queda inactivo, con su historia
    for (const id of [...guardado.keys()]) {
      if (!vivos.has(id)) { const {error} = await db.from('productos').update({activo: false}).eq('id', id); if (error) throw error; guardado.delete(id); }
    }
  }

  const clientesGuardados = new Map(); // cédula normalizada → JSON
  const normCI = ci => { let x = String(ci || '').toUpperCase().replace(/[.\s]/g, ''); if (/^[VEJGP]\d/.test(x)) x = x[0] + '-' + x.slice(1); return x; };
  const cFila = c => ({cedula_rif: normCI(c.ci), nombre: c.name, telefono: c.tel && c.tel !== '—' ? c.tel : null, correo: c.mail || null, direccion: c.dir || null});
  const deCliente = r => ({ci: r.cedula_rif, name: r.nombre, tel: r.telefono || '—', mail: r.correo || '', dir: r.direccion || '', visits: r.visitas,
    total: +r.total_usd, pts: r.puntos, last: r.ultima ? dmy(r.ultima) : '—', _id: r.id});
  async function cargarClientes() {
    const rs = await todo(() => db.from('clientes').select('*').eq('empresa_id', EMP()).order('ultima', {ascending: false, nullsFirst: false}));
    CLIENTS.length = 0; clientesGuardados.clear();
    rs.forEach(r => { const c = deCliente(r); CLIENTS.push(c); clientesGuardados.set(normCI(c.ci), JSON.stringify(cFila(c))); });
  }
  async function subirClientes() {
    for (const c of CLIENTS.slice()) {
      const f = cFila(c), j = JSON.stringify(f), k = normCI(c.ci);
      if (clientesGuardados.get(k) === j) continue;
      const q = c._id ? db.from('clientes').update(f).eq('id', c._id) : db.from('clientes').insert({...f, empresa_id: EMP()});
      const {data, error} = await q.select().single();
      if (error) {
        if (!c._id) { const i = CLIENTS.indexOf(c); if (i >= 0) CLIENTS.splice(i, 1); }
        render(); throw error;
      }
      c._id = data.id; c.ci = data.cedula_rif; clientesGuardados.set(normCI(c.ci), JSON.stringify(cFila(c)));
    }
  }
  // Después de cada acción del usuario, se guarda lo que haya cambiado
  const tras = () => setTimeout(() => { if (A().tipo === 'farmacia' && S.view !== 'login') sincronizar(); }, 0);
  ['click', 'submit', 'change'].forEach(ev => document.addEventListener(ev, tras));

  /* ---------------- Ventas de hoy (Mi turno, cierre, reportes) ---------------- */
  function ventasDeHoy() {
    S.inv = FX.n.FAC;
    const hoy = hoyVE();
    S.sales.length = 0; S.queue.length = 0;
    FX.docs.filter(d => d.tipo === 'FAC' && d.fecha === hoy).reverse().forEach(d => S.sales.push({
      t: d.hora, n: d.num, c: d.cli.n, m: d.pagos.length > 1 ? 'Mixto' : (d.pagos[0] || {}).k || '—', usd: r2(d.t.total / d.tasa), u: d.u, v: d.u,
      caja: '—', cont: d.cont, ctrl: d.ctrl, doc: d.id, it: d.lines.filter(l => l.pid).map(l => [l.pid, l.q, r2(l.pu / d.tasa)])}));
  }

  /* ---------------- Venta: la base emite la factura y descuenta los lotes ---------------- */
  let pase = false, venta = null;
  const fxEmitir = FX.emitir;
  FX.emitir = o => {
    const d = fxEmitir(o);
    if (venta && o.origen && o.origen.sale) { d.num = p8(venta.numero); d.ctrl = venta.numero_control || 'Pendiente de imprenta'; d.dbId = venta.id; d.cont = false; FX.n.FAC = venta.numero + 1; venta = null; }
    return d;
  };
  document.addEventListener('click', async e => {
    const b = e.target.closest('[data-act="emit"]'); if (!b || A().tipo !== 'farmacia') return;
    if (pase) { pase = false; return; }   // segunda vuelta: la pantalla arma el ticket
    e.preventDefault(); e.stopImmediatePropagation();
    if (S.medio === 'maquina') { avisar('La máquina fiscal no está conectada: factura con imprenta digital'); return; }
    if (!navigator.onLine) { avisar('Sin internet no se puede facturar todavía: el modo sin conexión viene en una próxima versión'); return; }
    const t = totals();
    if (t.rem > 0.005) { avisar('Falta cobrar ' + usd(t.rem)); return; }
    const txt = b.innerHTML; b.disabled = true; b.textContent = 'Facturando…';
    try {
      await sincronizar();   // por si hay un producto nuevo sin número de la base
      const {data: tasa} = await db.rpc('tasa_del_dia');
      if (tasa && Math.abs(+tasa - S.rate) >= 0.005) {
        S.rate = +tasa; openModal(payModal()); avisar(`La tasa BCV cambió a ${nf(S.rate)}: revisa el cobro y vuelve a facturar`); return;
      }
      const items = S.cart.flatMap(c => { const p = P.find(x => x.id === c.id); return segs(p, c.q).map(sg => ({producto_id: p.id, cantidad: sg.q, precio_usd: sg.pv ?? p.price})); });
      const cli = S.client ? {rif: S.client.ci, nombre: S.client.name, tel: S.client.tel && S.client.tel !== '—' ? S.client.tel : null} : {rif: 'V-00000000', nombre: 'Consumidor final'};
      const pagos = S.pays.map(p => ({metodo: p.k, monto_bs: r2(p.a * S.rate), divisa: !!p.div}));
      const {data, error} = await db.rpc('vender', {p_empresa: EMP(), p_cliente: cli, p_items: items, p_pagos: pagos});
      if (error) throw error;
      venta = data; const ids = items.map(i => i.producto_id), cliente = S.client;
      b.disabled = false; b.innerHTML = txt; pase = true; b.click();
      await recargar(ids); if (cliente) await cargarClientes();
      if (S.view !== 'pos') render(); else rerenderPOS();
    } catch (x) { avisar(C.msg(x)); }
    finally { if (b.isConnected) { b.disabled = false; if (b.textContent === 'Facturando…') b.innerHTML = txt; } }
  }, true);

  /* ---------------- Compra: los lotes entran por la base ---------------- */
  const doReceiveOriginal = doReceive;
  doReceive = function (ch) {
    (async () => {
      await sincronizar();
      const items = RECV.map(r => ({producto_id: r.id, lote: r.l, vence: r.e, cantidad: r.q, costo: r.c}));
      const ref = (document.getElementById('buy-ref') || {}).value || null;
      const {data, error} = await db.rpc('recibir_compra', {p_empresa: EMP(), p_items: items, p_referencia: ref});
      if (error) { avisar(C.msg(error)); return; }
      const ids = items.map(i => i.producto_id);
      doReceiveOriginal(ch);   // la pantalla calcula costo, precio por lote e historial
      // Cada lote toma el número que le dio la base; su costo y precio se guardan en la sincronización
      const deBase = {}; (data || []).forEach(l => { deBase[l.producto_id + '|' + l.lote + '|' + l.vence] = l; });
      const {data: ls} = await db.from('lotes').select('*').in('producto_id', ids).gt('cantidad', 0).order('vence');
      ids.forEach(id => {
        const p = P.find(x => x.id === id); if (!p) return;
        const local = {}; p.lots.forEach(l => { local[String(l.l).toUpperCase() + '|' + l.e] = l; });
        p.lots = (ls || []).filter(l => l.producto_id === id).map(l => {
          const x = lote(l), y = local[l.lote + '|' + l.vence];
          lotesGuardados.set(l.id, `${x.c}|${x.pv ?? ''}`);
          if (y) { x.c = y.c ?? x.c; if (y.pv != null) x.pv = y.pv; else delete x.pv; }
          return x;
        });
        p.stock = p.lots.reduce((t, l) => t + l.q, 0);
      });
      await sincronizar(); render();
    })().catch(x => avisar(C.msg(x)));
  };

  /* ---------------- Salida de inventario ---------------- */
  let salidaOk = false;
  document.addEventListener('submit', async e => {
    if (e.target.id !== 'salidaForm' || A().tipo !== 'farmacia') return;
    if (salidaOk) { salidaOk = false; return; }
    e.preventDefault(); e.stopImmediatePropagation();
    const f = e.target, p = P.find(x => x.id === +f.querySelector('#sa-p').value), l = p && p.lots.find(x => x.l === f.querySelector('#sa-l').value);
    const q = parseInt(f.querySelector('#sa-q').value) || 0, mot = f.querySelector('#sa-m').value, nota = (f.querySelector('#sa-n').value || '').trim();
    // Las mismas revisiones de la pantalla, antes de ir a la base
    if (!l || q <= 0 || q > l.q || (p.ctrl && S.role !== 'Farmacéutico') || (mot === 'Ajuste por conteo' && !nota)) { salidaOk = true; f.requestSubmit(); return; }
    if (!l.id) { avisar('Ese lote todavía no está en la base: recarga la página'); return; }
    const {error} = await db.rpc('salida_inventario', {p_lote: l.id, p_cantidad: q, p_motivo: mot + (nota ? ' · ' + nota : '')});
    if (error) { avisar(C.msg(error)); return; }
    salidaOk = true; f.requestSubmit();
    await recargar([p.id]); render();
  }, true);

  C.farmacia = {recargar, sincronizar};

  /* ---------------- Al entrar ---------------- */
  C.alEntrar(async a => {
    if (a.tipo !== 'farmacia') return;
    await cargarCatalogo();
    RECV = []; S.cart = []; S.cashea.length = 0; S.precioAvisos.length = 0;
    await cargarClientes();
    ventasDeHoy();
  });
})();
