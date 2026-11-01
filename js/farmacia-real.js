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
  if (!C || !C.listo || C.farmacia) return;
  const db = C.db;
  const A = () => C.acceso || {};
  const EMP = () => A().empresa_id;
  const EMPLEADOS = () => (0, eval)('EMP');   // la lista de empleados de la página (aquí EMP es el negocio)
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
      do { otraVez = false; await subirCatalogo(); await subirClientes(); await subirProveedores(); await subirGastos(); await subirColecciones(); await subirRecipes(); } while (otraVez);
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
  const tras = () => setTimeout(() => { if (A().tipo === 'farmacia' && S.view !== 'login' && navigator.onLine) sincronizar(); }, 0);
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
    const t = totals();
    if (t.rem > 0.005) { avisar('Falta cobrar ' + usd(t.rem)); return; }
    if (!navigator.onLine) { if (ventaSinInternet()) { pase = true; b.click(); } return; }
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
      await recargar(ids); if (cliente) await cargarClientes(); tablero(); libroVentas(); if (P.some(p => ids.includes(p.id) && p.ctrl)) await C.recargarControlados();
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
      const fac = factura();
      if (!fac.proveedor_id) { avisar(DROG.length ? 'Escoge la droguería' : 'Primero agrega la droguería en Proveedores y pagos'); return; }
      if (!fac.numero) { avisar('Escribe el número de la factura del proveedor'); const x = document.getElementById('fn'); x && x.focus(); return; }
      const {error} = await db.rpc('recibir_factura', {p_empresa: EMP(), p_factura: fac, p_items: items});
      if (error) { avisar(/duplicate/i.test(error.message) ? `La factura ${fac.numero} de esa droguería ya está registrada` : C.msg(error)); return; }
      const ids = items.map(i => i.producto_id);
      doReceiveOriginal(ch);   // la pantalla calcula costo, precio por lote e historial
      // Cada lote toma el número que le dio la base; su costo y precio se guardan en la sincronización
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
      S.fac = {}; await cargarCompras(); await C.recargarControlados();
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
    await recargar([p.id]); if (p.ctrl) await C.recargarControlados(); render();
  }, true);

  /* ---------------- Proveedores ---------------- */
  const gProv = new Map();
  const normRif = r => { const x = String(r || '').toUpperCase().replace(/[.\s]/g, '').replace(/^([JGVEP])-?(\d{8})-?(\d)$/, '$1-$2-$3'); return x || null; };
  const provFila = d => ({nombre: d.n, rif: normRif(d.rif), credito_dias: d.cred ?? 15, telefono: d.tel && d.tel !== '—' ? d.tel : null});
  async function cargarProveedores() {
    const rs = await todo(() => db.from('proveedores').select('*').eq('empresa_id', EMP()).eq('activo', true).order('nombre'));
    DROG.length = 0; gProv.clear();
    rs.forEach(r => { const d = {n: r.nombre, cred: r.credito_dias, tel: r.telefono || '—', rif: r.rif || '', _id: r.id}; DROG.push(d); gProv.set(d._id, JSON.stringify(provFila(d))); });
  }
  async function subirProveedores() {
    for (const d of DROG.slice()) {
      const f = provFila(d), j = JSON.stringify(f);
      if (d._id && gProv.get(d._id) === j) continue;
      const q = d._id ? db.from('proveedores').update(f).eq('id', d._id) : db.from('proveedores').insert({...f, empresa_id: EMP()});
      const {data, error} = await q.select().single();
      if (error) { if (!d._id) DROG.splice(DROG.indexOf(d), 1); else d.rif = ''; render(); throw /check/i.test(error.message) ? new Error('El RIF del proveedor debe quedar así: J-12345678-9') : error; }
      d._id = data.id; d.rif = data.rif || ''; gProv.set(d._id, j);
    }
  }

  /* ---------------- Compras: libro de compras y cuentas por pagar ---------------- */
  let COMPRAS = [];
  const delMes = f => f.slice(0, 7) === hoyVE().slice(0, 7);
  async function cargarCompras() {
    COMPRAS_LIBRO.length = 0;
    if (!['dueno', 'gerente', 'regente', 'almacen'].includes(A().rol)) return;
    const desde = new Date(Date.now() - 400 * 864e5).toISOString().slice(0, 10);
    COMPRAS = await todo(() => db.from('compras').select('*').eq('empresa_id', EMP()).gte('fecha', desde).order('fecha'));
    COMPRAS.filter(c => delMes(c.fecha)).forEach(c => COMPRAS_LIBRO.push([dmy(c.fecha), c.tipo, c.numero, c.control || '', c.rif || '', c.proveedor, +c.exento_usd, +c.gravable_usd]));
  }
  FX_SYS.compras = () => COMPRAS.filter(c => delMes(c.fecha)).map(c => ({f: c.fecha, tipo: c.tipo, num: c.numero, ctrl: c.control || '', afecta: '', rif: c.rif || '',
    prov: c.proveedor, ex: r2(c.exento_usd * c.tasa), bg: r2(c.gravable_usd * c.tasa)}));
  // Lo escrito en la factura del proveedor se recuerda aunque la pantalla se redibuje
  S.fac = {};
  document.addEventListener('input', e => { if (['dr', 'fn', 'fc', 'fd'].includes(e.target.id)) S.fac[e.target.id] = e.target.value; });
  document.addEventListener('change', e => { if (e.target.id === 'dr') S.fac.dr = e.target.value; });
  const factura = () => {
    const v = id => ((document.getElementById(id) || {}).value || S.fac[id] || '').trim();
    const d = DROG.find(x => x.n === v('dr')) || (DROG.length === 1 ? DROG[0] : null);
    return {proveedor_id: d && d._id, numero: v('fn'), control: v('fc'), fecha: v('fd') || hoyVE()};
  };
  const diasA = (f, n) => { const d = new Date(f + 'T12:00:00'); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };
  V.suppliers = () => {
    const deuda = COMPRAS.filter(c => c.total_usd - c.pagado_usd > 0.004).sort((a, b) => (a.vence || '').localeCompare(b.vence || ''));
    const tot = deuda.reduce((t, c) => t + (c.total_usd - c.pagado_usd), 0), semana = diasA(hoyVE(), 7);
    const pronto = deuda.filter(c => c.vence && c.vence <= semana), totPronto = pronto.reduce((t, c) => t + (c.total_usd - c.pagado_usd), 0);
    const delMesC = COMPRAS.filter(c => delMes(c.fecha));
    const estado = c => { const d = Math.round((new Date(c.vence + 'T12:00:00') - new Date(hoyVE() + 'T12:00:00')) / 864e5);
      return d < 0 ? ['bad', `Vencida hace ${-d} ${d === -1 ? 'día' : 'días'}`] : d <= 7 ? ['warn', d === 0 ? 'Vence hoy' : `Vence en ${d} ${d === 1 ? 'día' : 'días'}`] : ['info', 'Al día']; };
    const dueno = ['dueno', 'gerente'].includes(A().rol);
    return `<p class="lead">Lo que se le debe a cada droguería, con sus días de crédito. Cada factura de compra entra aquí y al Libro de Compras al recibirla en Compras.</p>
    <div class="kpis"><div class="kpi"><span class="l">Total por pagar</span><span class="v">${usd(tot)}</span><span class="s num">${bs(tot * S.rate)}</span></div>
    <div class="kpi"><span class="l">Vence esta semana</span><span class="v" ${totPronto ? 'style="color:var(--warn)"' : ''}>${usd(totPronto)}</span><span class="s">${pronto.length} ${pronto.length === 1 ? 'factura' : 'facturas'}</span></div>
    <div class="kpi"><span class="l">Compras del mes</span><span class="v">${usd(delMesC.reduce((t, c) => t + +c.total_usd, 0))}</span><span class="s">${delMesC.length} ${delMesC.length === 1 ? 'factura' : 'facturas'}</span></div></div>
    <section class="panel"><div class="hd"><h2>Facturas por pagar</h2></div><div class="bd flush tbl-wrap"><table><thead><tr><th>Droguería</th><th>Factura</th><th>Emitida</th><th>Vence</th><th class="r">Total $</th><th class="r">Saldo $</th><th>Estado</th><th></th></tr></thead><tbody>
    ${deuda.map(c => { const [k, t] = estado(c); return `<tr><td><b>${C.esc(c.proveedor)}</b></td><td class="num">${C.esc(c.numero)}</td><td class="num">${dmy(c.fecha)}</td><td class="num">${c.vence ? dmy(c.vence) : '—'}</td>
      <td class="r">${nf(c.total_usd)}</td><td class="r"><b>${nf(c.total_usd - c.pagado_usd)}</b></td><td><span class="pill ${k}">${t}</span></td>
      <td>${dueno ? `<button class="btn sm" data-act="fr-pagar" data-id="${c.id}">Registrar pago</button>` : ''}</td></tr>`; }).join('') || '<tr><td colspan="8" class="muted">No se le debe nada a ninguna droguería.</td></tr>'}</tbody></table></div></section>
    <section class="panel"><div class="hd"><h2>Droguerías</h2><span class="muted small">El RIF sale en el Libro de Compras</span></div><div class="bd flush tbl-wrap"><table><thead><tr><th>Nombre</th><th>RIF</th><th>Días de crédito</th><th>Contacto</th></tr></thead><tbody>
    ${DROG.map((d, i) => `<tr><td><b>${C.esc(d.n)}</b></td><td><input class="input num" data-drog="${i}" data-f="rif" value="${C.esc(d.rif || '')}" placeholder="J-00000000-0"></td>
      <td><input class="input num" data-drog="${i}" data-f="cred" value="${d.cred}" inputmode="numeric" style="max-width:90px"></td><td><input class="input" data-drog="${i}" data-f="tel" value="${C.esc(d.tel === '—' ? '' : d.tel)}"></td></tr>`).join('')}
    <tr><td colspan="3"><input id="drogname" class="input" placeholder="Nombre de la droguería nueva"></td><td><button class="btn" data-act="drogadd">${ic('plus')}Agregar</button></td></tr></tbody></table></div></section>`;
  };
  document.addEventListener('click', e => {
    const b = e.target.closest('[data-act="fr-pagar"]'); if (!b) return;
    e.stopImmediatePropagation();
    const c = COMPRAS.find(x => x.id === +b.dataset.id), saldo = r2(c.total_usd - c.pagado_usd);
    openModal(`<div class="sheet" role="dialog" aria-modal="true" style="max-width:440px"><div class="hd"><h2>Pago a ${C.esc(c.proveedor)}</h2><button class="x" data-act="close" aria-label="Cerrar">${ic('x')}</button></div>
      <form class="bd" id="fr-pago" data-id="${c.id}" style="display:grid;gap:10px"><p style="margin:0">Factura ${C.esc(c.numero)} · saldo <b>${usd(saldo)}</b></p>
      <div class="field"><label for="fr-m">Monto en $</label><input id="fr-m" class="input num" inputmode="decimal" value="${nf(saldo)}"></div>
      <div class="field"><label for="fr-met">Cómo se pagó</label><select id="fr-met" class="input">${['Transferencia', 'Pago móvil', 'Efectivo $', 'Zelle'].map(x => `<option>${x}</option>`).join('')}</select></div>
      <button class="btn primary big" type="submit">${ic('check')}Registrar pago</button></form></div>`);
  }, true);
  document.addEventListener('submit', async e => {
    if (e.target.id !== 'fr-pago') return;
    e.preventDefault(); e.stopImmediatePropagation();
    const m = parseVE(document.getElementById('fr-m').value);
    const {error} = await db.rpc('pagar_compra', {p_compra: +e.target.dataset.id, p_monto: m, p_metodo: document.getElementById('fr-met').value});
    if (error) { avisar(C.msg(error)); return; }
    await cargarCompras(); closeModal(); render(); avisar('Pago registrado');
  }, true);

  /* ---------------- Gastos ---------------- */
  const gGastos = new Map();
  const isoDe = f => /^\d{2}\/\d{2}\/\d{4}$/.test(f) ? f.slice(6) + '-' + f.slice(3, 5) + '-' + f.slice(0, 2) : hoyVE();
  const gastoFila = x => { const {f, usd: u, _id, ...datos} = x; return {fecha: isoDe(f), usd: +u || 0, datos}; };
  async function cargarGastos() {
    S.gastos.length = 0; gGastos.clear();
    if (!['dueno', 'gerente'].includes(A().rol)) return;
    const desde = new Date(Date.now() - 400 * 864e5).toISOString().slice(0, 10);
    const rs = await todo(() => db.from('gastos').select('*').eq('empresa_id', EMP()).eq('anulado', false).gte('fecha', desde).order('fecha'));
    rs.forEach(r => { const x = {ret: null, fijo: false, ...(r.datos || {}), f: dmy(r.fecha), usd: +r.usd, _id: r.id}; S.gastos.push(x); gGastos.set(x._id, JSON.stringify(gastoFila(x))); });
  }
  async function subirGastos() {
    if (!['dueno', 'gerente'].includes(A().rol)) return;
    const vivos = new Set();
    for (const x of S.gastos.slice()) {
      const f = gastoFila(x), j = JSON.stringify(f);
      if (x._id) { vivos.add(x._id); if (gGastos.get(x._id) === j) continue; const {error} = await db.from('gastos').update(f).eq('id', x._id); if (error) throw error; gGastos.set(x._id, j); continue; }
      const {data, error} = await db.from('gastos').insert({...f, empresa_id: EMP()}).select().single(); if (error) throw error;
      x._id = data.id; vivos.add(x._id); gGastos.set(x._id, j);
    }
    for (const id of [...gGastos.keys()]) if (!vivos.has(id)) { const {error} = await db.from('gastos').update({anulado: true}).eq('id', id); if (error) throw error; gGastos.delete(id); }
  }

  /* ---------------- Configuración y listas guardadas ---------------- */
  const COL = [
    ['config', () => CFG, v => Object.assign(CFG, v), null],
    ['secciones', () => S.secs, v => { S.secs.length = 0; S.secs.push(...v); }, null],
    ['privado_cuentas', () => CUENTAS, v => { CUENTAS.length = 0; CUENTAS.push(...v); }, []],
    ['empresa_extra', () => ({wa: EMPRESA.wa, mail: EMPRESA.mail}), v => { EMPRESA.wa = v.wa || ''; EMPRESA.mail = v.mail || ''; }, {wa: '', mail: ''}],
    ['equipo_fallas', () => S.fallas, v => { S.fallas.length = 0; S.fallas.push(...v); }, []],
    ['equipo_cotizaciones', () => S.cots, v => { S.cots.length = 0; S.cots.push(...v); }, []],
    ['equipo_notas', () => S.notas, v => { S.notas.length = 0; S.notas.push(...v); }, []],
    ['equipo_cashea', () => S.cashea, v => { S.cashea.length = 0; S.cashea.push(...v); }, []],
    // Nómina: datos de los empleados y novedades del período (solo dueño y gerente)
    ['privado_nomina_empleados', () => EMPLEADOS(), v => { EMPLEADOS().length = 0; EMPLEADOS().push(...v); }, []],
    ['privado_nomina_novedades', () => S.nov, v => { Object.keys(S.nov).forEach(k => delete S.nov[k]); Object.assign(S.nov, v); }, {}],
    // Cada quincena pagada: quién cobró y cuánto (la quincena de hoy queda «pagada» si ya está aquí)
    ['privado_nomina_pagos', () => S.nomPagos || [], v => { S.nomPagos = v; S.nomEstado = v.some(x => x.periodo === QUIN.id) ? 'pagada' : ''; }, []]];
  const gCol = new Map();
  const puedeCol = n => n.startsWith('equipo_') || ['dueno', 'gerente'].includes(A().rol);
  async function cargarColecciones() {
    const {data} = await db.from('colecciones').select('nombre,datos').eq('empresa_id', EMP());
    const por = {}; (data || []).forEach(r => { por[r.nombre] = r.datos; });
    COL.forEach(([n, get, set, vacio]) => { if (por[n] !== undefined) set(por[n]); else if (vacio !== null) set(vacio); gCol.set(n, JSON.stringify(get())); });
  }
  async function subirColecciones() {
    for (const [n, get] of COL) {
      if (!puedeCol(n)) continue;
      const j = JSON.stringify(get()); if (gCol.get(n) === j) continue;
      const {error} = await db.from('colecciones').upsert({empresa_id: EMP(), nombre: n, datos: JSON.parse(j), actualizado: new Date().toISOString()}, {onConflict: 'empresa_id,nombre'});
      if (error) throw error; gCol.set(n, j);
    }
  }
  /* ---------------- Tablero: ventas por día y por cajero, de las facturas reales ---------------- */
  function tablero() {
    const dia = new Intl.DateTimeFormat('es-VE', {weekday: 'short', day: 'numeric', timeZone: 'America/Caracas'});
    DAYS.length = 0;
    for (let i = 6; i >= 1; i--) {
      const f = diasA(hoyVE(), -i), v = FX.docs.filter(d => d.tipo === 'FAC' && d.fecha === f).reduce((t, d) => t + d.t.total / d.tasa, 0);
      DAYS.push({d: dia.format(new Date(f + 'T12:00:00')).replace(/^./, x => x.toUpperCase()).replace('.', ''), v: r2(v)});
    }
    USERS_TODAY.length = 0;
    const por = {}; S.sales.forEach(s => { const k = s.u || '—'; por[k] = por[k] || {u: k, caja: s.caja || '—', usd: 0, n: 0}; por[k].usd = r2(por[k].usd + s.usd); por[k].n++; });
    USERS_TODAY.push(...Object.values(por).sort((a, b) => b.usd - a.usd));
    const nombres = [...new Set([A().nombre, ...S.sales.map(s => s.u)].filter(Boolean))];
    VENDS.length = 0; VENDS.push(...nombres);
  }

  /* ---------------- Movimientos de inventario (salidas y ajustes) ---------------- */
  async function cargarMovimientos() {
    S.movs.length = 0;
    if (!['dueno', 'gerente', 'regente', 'almacen'].includes(A().rol)) return;
    const desde = new Date(Date.now() - 60 * 864e5).toISOString();
    const [rs, {data: per}] = await Promise.all([
      todo(() => db.from('movimientos').select('*, lotes(lote)').eq('empresa_id', EMP()).in('tipo', ['salida', 'ajuste']).gte('fecha', desde).order('id', {ascending: false})),
      db.from('perfiles').select('user_id,nombre')]);
    const nom = {}; (per || []).forEach(p => { nom[p.user_id] = p.nombre; });
    rs.forEach(m => { const [mot, ...nota] = String(m.motivo || '').split(' · ');
      S.movs.push({f: dmy(new Intl.DateTimeFormat('en-CA', {timeZone: 'America/Caracas'}).format(new Date(m.fecha))), h: new Date(m.fecha).toLocaleTimeString('es-VE', {hour: '2-digit', minute: '2-digit', hour12: false, timeZone: 'America/Caracas'}),
        id: m.producto_id, l: m.lotes ? m.lotes.lote : '', q: Math.abs(+m.cantidad), mot, nota: nota.join(' · '), u: nom[m.usuario] || ''}); });
  }

  /* ---------------- Ganancias y gastos: cifras de la base ---------------- */
  let resumen = [], resumenEn = 0;
  async function cargarResumen() {
    if (!['dueno', 'gerente'].includes(A().rol)) return;
    const {data, error} = await db.rpc('resumen_mensual', {p_empresa: EMP(), p_meses: 3});
    if (error) return;
    resumen = Array.isArray(data) ? data : []; resumenEn = Date.now();
    const m = resumen[resumen.length - 1] || {};
    FIN.mes = {ventas: +m.ventas_usd || 0, costo: +m.costo_usd || 0, gastos: +m.gastos_usd || 0};
  }
  FIN.meses = () => resumen.map((r, i) => { const n = new Date(r.mes + 'T12:00:00').toLocaleDateString('es-VE', {month: 'long'});
    return [n.replace(/^./, x => x.toUpperCase()) + (i === resumen.length - 1 ? ' (en curso)' : ''), +r.ventas_usd, +r.costo_usd, +r.gastos_usd]; });
  FIN.proximos = () => {
    const hoy = hoyVE(), hasta = diasA(hoy, 15), dias = f => Math.round((new Date(f + 'T12:00:00') - new Date(hoy + 'T12:00:00')) / 864e5), out = [];
    COMPRAS.filter(c => c.total_usd - c.pagado_usd > 0.004 && c.vence && c.vence <= hasta)
      .forEach(c => out.push([dmy(c.vence), 'Droguería', `${c.proveedor}, factura ${c.numero}`, r2(c.total_usd - c.pagado_usd), Math.max(dias(c.vence), 0)]));
    S.gastos.filter(x => x.fijo).forEach(x => {
      const d = +String(x.f).slice(0, 2) || 1, [y, mo] = hoy.split('-').map(Number);
      let f = new Date(y, mo - 1, d); if (f.toISOString().slice(0, 10) < hoy) f = new Date(y, mo, d);
      const iso = new Intl.DateTimeFormat('en-CA').format(f);
      if (iso <= hasta && !out.some(o => o[1] === x.cat && o[2] === x.desc)) out.push([dmy(iso), x.cat, x.desc, x.usd, dias(iso)]);
    });
    return out.sort((a, b) => a[4] - b[4]);
  };
  const vFinance = V.finance;
  V.finance = () => {
    if (Date.now() - resumenEn > 15000) cargarResumen().then(() => { if (S.view === 'finance') render(); });
    return vFinance();
  };

  /* ---------------- Récipes, médicos y libro de controlados ---------------- */
  const veSalud = () => ['dueno', 'gerente', 'regente'].includes(A().rol);
  const gMed = new Set();
  const hmDe = f => new Date(f).toLocaleTimeString('es-VE', {hour: '2-digit', minute: '2-digit', hour12: false, timeZone: 'America/Caracas'});
  const fechaDe = f => dmy(new Intl.DateTimeFormat('en-CA', {timeZone: 'America/Caracas'}).format(new Date(f)));
  const medIdx = (n, mpps) => { if (!n) return 0; let i = MEDICOS.findIndex(m => m.n === n); if (i < 0) { MEDICOS.push({n, mpps: mpps || '—', esp: '', rx: 0}); i = MEDICOS.length - 1; } return i; };
  async function cargarRecipes() {
    MEDICOS.length = 0; RX.length = 0; CTRL.length = 0; gMed.clear();
    const ms = await todo(() => db.from('medicos').select('*').eq('empresa_id', EMP()).eq('activo', true).order('nombre'));
    ms.forEach(m => { MEDICOS.push({n: m.nombre, mpps: m.mpps || '—', esp: m.especialidad || '', rx: 0}); gMed.add(m.nombre); });
    S.rxN = 1;
    if (!veSalud()) return;
    const desde = new Date(Date.now() - 730 * 864e5).toISOString();   // la ley pide guardarlos al menos 2 años
    const [rs, ls] = await Promise.all([
      todo(() => db.from('recipes').select('*').eq('empresa_id', EMP()).gte('fecha', desde).order('numero', {ascending: false})),
      todo(() => db.from('libro_controlados').select('*').eq('empresa_id', EMP()).gte('fecha', desde).order('id'))]);
    rs.forEach(r => { const i = medIdx(r.medico, r.mpps); MEDICOS[i].rx++;
      RX.push({...(r.datos || {}), id: r.numero, f: fechaDe(r.fecha), h: hmDe(r.fecha), ci: r.paciente_ci, pac: r.paciente, med: i, tipo: r.tipo, num: r.numero_especial || undefined,
        prod: r.producto, rec: +r.recetado, desp: +r.despachado, u: r.unidad || '', cron: r.cronico, orig: r.original || '', _id: r.id}); });
    S.rxN = (rs[0] ? +rs[0].numero : 0) + 1;
    ls.forEach(l => CTRL.push([fechaDe(l.fecha), l.producto, l.concepto, l.origen || '—', l.paciente_ci || '—', l.lote || '—', +l.entrada, +l.salida]));
  }
  /* Alertas de pacientes: la regente las ve completas; la caja solo los principios a frenar */
  const dig = x => String(x || '').replace(/\D/g, '');
  async function cargarAlertas() {
    Object.keys(ALERTAS).forEach(k => delete ALERTAS[k]); Object.keys(ALERTAS_LISTA).forEach(k => delete ALERTAS_LISTA[k]);
    if (!veSalud()) return;
    const rs = await todo(() => db.from('alertas_pacientes').select('*').eq('empresa_id', EMP()).eq('activo', true).order('id'));
    rs.forEach(a => { (ALERTAS_LISTA[dig(a.cedula)] = ALERTAS_LISTA[dig(a.cedula)] || []).push(a);
      const x = ALERTAS[a.cedula] = ALERTAS[a.cedula] || {txt: '', acts: [], por: ''}; x.txt = [x.txt, a.texto].filter(Boolean).join(' · '); x.acts.push(...a.principios); });
  }
  const preguntadas = new Set();
  document.addEventListener('click', () => setTimeout(async () => {   // la caja pregunta por el cliente escogido
    if (A().tipo !== 'farmacia' || veSalud() || !S.client || preguntadas.has(S.client.ci)) return;
    const ci = S.client.ci; preguntadas.add(ci);
    const {data} = await db.rpc('alerta_principios', {p_empresa: EMP(), p_cedula: ci});
    if (data && data.length) ALERTAS[ci] = {txt: 'Consulta a la regente antes de vender este producto a este cliente', acts: data, por: ''};
  }, 0));
  document.addEventListener('click', async e => {
    const b = e.target.closest('[data-act="rxala"],[data-act="rxalq"]'); if (!b) return;
    e.stopImmediatePropagation();
    if (b.dataset.act === 'rxala') {
      const texto = (document.getElementById('rx-alt').value || '').trim(), pr = (document.getElementById('rx-alp').value || '').split(',').map(x => x.trim()).filter(Boolean);
      if (!texto || !pr.length) { avisar('Escribe la alerta y al menos un principio activo'); return; }
      const ci = RX.find(r => dig(r.ci) === dig(S.rxPac)); 
      const {error} = await db.from('alertas_pacientes').insert({empresa_id: EMP(), cedula: ci ? ci.ci : S.rxPac, texto, principios: pr});
      if (error) { avisar(C.msg(error)); return; }
    } else {
      const {error} = await db.from('alertas_pacientes').update({activo: false}).eq('id', +b.dataset.id);
      if (error) { avisar(C.msg(error)); return; }
    }
    await cargarAlertas(); render(); avisar(b.dataset.act === 'rxala' ? 'Alerta guardada: la caja avisará' : 'Alerta quitada');
  }, true);
  C.recargarControlados = async () => { if (!veSalud()) return; try { await cargarRecipes(); } catch (x) { console.error(x); } };
  const SUYOS_RX = ['id', 'f', 'h', 'ci', 'pac', 'med', 'tipo', 'num', 'prod', 'rec', 'desp', 'u', 'cron', 'orig', '_id'];
  async function subirRecipes() {
    for (const m of MEDICOS) {
      if (gMed.has(m.n)) continue;
      const {error} = await db.from('medicos').upsert({empresa_id: EMP(), nombre: m.n, mpps: m.mpps && m.mpps !== '—' ? m.mpps : null, especialidad: m.esp || null}, {onConflict: 'empresa_id,nombre'});
      if (error) throw error; gMed.add(m.n);
    }
    if (!veSalud()) return;
    for (const r of RX.slice()) {
      if (r._id) continue;
      const m = MEDICOS[r.med] || {}, pr = P.find(p => p.name === r.prod), datos = {};
      Object.keys(r).forEach(k => { if (!SUYOS_RX.includes(k)) datos[k] = r[k]; });
      const {data, error} = await db.from('recipes').insert({empresa_id: EMP(), paciente_ci: r.ci, paciente: r.pac, medico: m.n || null, mpps: m.mpps && m.mpps !== '—' ? m.mpps : null,
        tipo: r.tipo, numero_especial: r.num || null, producto_id: pr ? pr.id : null, producto: r.prod, recetado: r.rec, despachado: r.desp, unidad: r.u, cronico: !!r.cron, original: r.orig, datos}).select().single();
      if (error) { RX.splice(RX.indexOf(r), 1); render();
        throw /duplicate/i.test(error.message) ? new Error(`El récipe especial N° ${r.num} ya está registrado: no se puede usar otra vez`) : error; }
      r._id = data.id; r.id = data.numero; S.rxN = Math.max(S.rxN, data.numero + 1);
    }
  }
  // «Otro médico (agregar)»: nombre y MPPS ahí mismo, en el récipe
  document.addEventListener('change', e => {
    if (e.target.id !== 'rx-med') return;
    const box = document.getElementById('rx-medn');
    if (e.target.value !== 'new') { if (box) box.remove(); return; }
    e.stopImmediatePropagation();
    if (!box) e.target.closest('.field').insertAdjacentHTML('afterend', `<div id="rx-medn" class="grid g2" style="gap:10px;grid-column:1/-1">
      <div class="field"><label for="rx-mn">Nombre del médico</label><input id="rx-mn" class="input" placeholder="Dra. Laura Sosa"></div>
      <div class="field"><label for="rx-mm">MPPS</label><input id="rx-mm" class="input num" placeholder="61.877"></div></div>`);
    document.getElementById('rx-mn').focus();
  }, true);
  document.addEventListener('submit', e => {
    if (e.target.id !== 'rxForm') return;
    const sel = document.getElementById('rx-med'); if (!sel || sel.value !== 'new') return;
    const n = (document.getElementById('rx-mn').value || '').trim(), mpps = (document.getElementById('rx-mm').value || '').trim();
    if (!n || !mpps) { e.preventDefault(); e.stopImmediatePropagation(); avisar('Escribe el nombre y el MPPS del médico'); return; }
    const i = medIdx(n, mpps);
    sel.insertAdjacentHTML('afterbegin', `<option value="${i}">${C.esc(n)}</option>`); sel.value = String(i);
  }, true);

  /* ---------------- Cuentas y bancos: lo que la base sabe de verdad ---------------- */
  FIN.compras = () => COMPRAS.slice(-6).reverse().map(c => [c.proveedor, c.numero, dmy(c.fecha), +c.total_usd, 'Recibida']);
  V.banks = () => {
    const hoy = hoyVE(), docs = FX.docs.filter(d => d.tipo === 'FAC' && d.fecha === hoy), por = {};
    docs.forEach(d => d.pagos.forEach(p => { const k = p.k || '—'; por[k] = por[k] || {bs: 0, usd: 0, n: 0}; if (p.usd != null) por[k].usd += +p.usd; else por[k].bs += +p.bs || 0; por[k].n++; }));
    const tot = Object.values(por).reduce((t, x) => t + x.usd + x.bs / S.rate, 0);
    const deuda = COMPRAS.filter(c => c.total_usd - c.pagado_usd > 0.004).sort((a, b) => (a.vence || '').localeCompare(b.vence || ''));
    const cz = S.cashea, czPend = cz.reduce((a, x) => a + (x.fin - x.cuota * x.pagadas), 0);
    return `<p class="lead">Cuánto entró hoy por cada forma de pago, cuánto le deben a la farmacia (cuotas de Cashea) y cuánto debe a las droguerías.</p>
    <div class="kpis k3">${Object.entries(por).map(([k, x]) => `<div class="kpi"><span class="l">${C.esc(k)} · hoy</span><span class="v">${x.usd ? usd(x.usd) : bs(x.bs)}</span><span class="s num">${x.n} ${x.n === 1 ? 'pago' : 'pagos'}</span></div>`).join('')}
      <div class="kpi hero"><span class="l">Cobrado hoy</span><span class="v">${usd(tot)}</span><span class="s num">${bs(tot * S.rate)}</span></div></div>
    <div class="grid g-dash">
      <section class="panel"><div class="hd"><h2>Cuentas de la farmacia</h2><a href="#config" data-act="nav" data-v="config" class="small" style="color:var(--azul)">Editar en Configuración</a></div><div class="bd">
        ${CUENTAS.map(c => `<div class="stat"><span><b>${C.esc(c.b)}</b> · ${C.esc(c.t || '')}</span><span class="small muted num">${C.esc(c.n || '')}</span></div>`).join('') || '<p class="small muted" style="margin:0">Todavía no hay cuentas registradas.</p>'}
        <p class="small muted" style="margin-top:10px">La conciliación con el estado de cuenta del banco y el diferencial cambiario llegan en una próxima versión: necesitan los movimientos del banco.</p></div></section>
      <section class="panel"><div class="hd"><h2>Por pagar a droguerías</h2><span class="muted small num">${usd(deuda.reduce((t, c) => t + c.total_usd - c.pagado_usd, 0))}</span></div><div class="bd flush list">
        ${deuda.map(c => `<div class="it"><div class="t"><b>${C.esc(c.proveedor)} · Factura ${C.esc(c.numero)}</b><span class="small muted num">Vence ${c.vence ? dmy(c.vence) : '—'}</span></div><div class="num" style="font-weight:700">${usd(c.total_usd - c.pagado_usd)}</div></div>`).join('') || '<div class="it"><div class="t"><span class="muted">No se le debe a ninguna droguería.</span></div></div>'}
      </div></section></div>
    <section class="panel"><div class="hd"><h2>Por cobrar · Cashea</h2><span class="muted small num">${usd(czPend)}</span></div><div class="bd flush tbl-wrap"><table><thead><tr><th>Cliente</th><th class="r">Cuotas</th><th class="r">Pendiente $</th><th>Próxima</th></tr></thead>
      <tbody>${cz.map(x => `<tr><td>${C.esc(x.c)}<div class="small muted num">Compra ${x.f} · ${usd(x.total)}</div></td><td class="r">${x.pagadas}/${CASHEA_CUOTAS}</td><td class="r">${nf(x.fin - x.cuota * x.pagadas)}</td><td class="num small">${usd(x.cuota)}</td></tr>`).join('') || '<tr><td colspan="4" class="muted">No hay ventas con Cashea pendientes.</td></tr>'}</tbody></table></div></section>`;
  };

  /* ---------------- Libro de ventas del módulo fiscal: las facturas del mes ---------------- */
  function libroVentas() {
    LIBRO.length = 0; LIBRO_DIG.length = 0;
    FX.docs.forEach(d => {
      const s = d.tipo === 'NC' ? -1 : 1, t = d.t || {}, k = x => r2(s * (+x || 0) / d.tasa);
      LIBRO.push([dmy(d.fecha), (d.tipo === 'FAC' ? 'Factura ' : d.tipo === 'NC' ? 'Nota de crédito ' : 'Nota de débito ') + d.num, d.cli.id || '—', d.cli.n, k(t.total), k(t.ex), k(t.bg), k(t.ivg), k(d.igtf)]);
      LIBRO_DIG.push(`${d.tipo === 'FAC' ? 'Factura' : d.tipo === 'NC' ? 'Nota de crédito' : 'Nota de débito'} ${d.num} · control ${d.ctrl}`);
    });
  }

  /* ---------------- Pantallas de la fase 2 que siguen siendo muestra ---------------- */
  const aviso = t => `<p class="fx-aviso" style="margin:0 0 12px">${ic('alert')}<span><b>Fase 2 · muestra.</b> ${t}</span></p>`;
  ['store', 'branches'].forEach(v => { const o = V[v]; if (o) V[v] = () => aviso('Esta pantalla muestra cómo funcionará; las cifras no son reales todavía.') + o(); });
  const vLoyalty = V.loyalty; V.loyalty = () => aviso('Los puntos ya se suman solos con cada venta (1 por dólar). El canje en la caja y los recordatorios por WhatsApp llegan en la fase 2.') + vLoyalty();
  // Proveedores y récipes ya son reales: salen de «Fase 2» y van a su lugar en el menú
  (() => { const f2 = NAV.find(g => g.f2); if (!f2) return;
    const mover = (v, grupo) => { const i = f2.items.findIndex(it => it[1] === v); if (i < 0) return; const [it] = f2.items.splice(i, 1); const g = NAV.find(x => x.g === grupo); if (g) g.items.push(it); const j = F2.indexOf(v); if (j >= 0) F2.splice(j, 1); };
    mover('recipes', 'Operación'); mover('suppliers', 'Administración'); })();

  /* ---------------- Ventas sin internet: talonario de contingencia y cola ---------------- */
  const COLA = () => C.leerLocal('cola') || [];
  const guardarCola = c => C.guardarLocal('cola', c);
  async function siguienteTalonario() {
    const F = FX.F, desde = +F.talDesde || 1;
    let n = desde;
    try {
      const {data} = await db.from('documentos').select('numero').eq('empresa_id', EMP()).eq('origen', 'contingencia').order('numero', {ascending: false}).limit(1);
      if (data && data[0]) n = Math.max(n, +data[0].numero + 1);
    } catch (_) {}
    COLA().forEach(v => { n = Math.max(n, v.numero + 1); });
    const loc = C.leerLocal('talonario'); if (loc) n = Math.max(n, +loc);
    FX.n.tal = n;
  }
  function ventaSinInternet() {
    const F = FX.F, n = FX.n.tal;
    if (!F.talHasta || n < (+F.talDesde || 1) || n > +F.talHasta) {
      avisar('Sin internet y sin talonario de contingencia disponible: cárgalo en Configuración (desde y hasta)'); return false; }
    const items = S.cart.flatMap(c => { const p = P.find(x => x.id === c.id); return segs(p, c.q).map(sg => ({producto_id: p.id, cantidad: sg.q, precio_usd: sg.pv ?? p.price})); });
    const cli = S.client ? {rif: S.client.ci, nombre: S.client.name, tel: S.client.tel && S.client.tel !== '—' ? S.client.tel : null} : {rif: 'V-00000000', nombre: 'Consumidor final'};
    const cola = COLA();
    cola.push({numero: n, fecha: new Date().toISOString(), cliente: cli, items, pagos: S.pays.map(p => ({metodo: p.k, monto_bs: r2(p.a * S.rate), divisa: !!p.div})), usuario: A().nombre});
    guardarCola(cola); C.guardarLocal('talonario', n + 1);
    return true;
  }
  let subiendo = false;
  async function subirCola() {
    if (subiendo || !navigator.onLine || A().tipo !== 'farmacia') return;
    const cola = COLA(); if (!cola.length) return;
    subiendo = true; let ok = 0, malas = [];
    try {
      for (const v of cola) {
        const {error} = await db.rpc('vender', {p_empresa: EMP(), p_cliente: v.cliente, p_items: v.items, p_pagos: v.pagos, p_origen: 'contingencia', p_numero: v.numero, p_fecha: v.fecha});
        if (!error || /duplicate/i.test(error.message)) ok++;            // repetida: ya había subido
        else if (/Failed to fetch|network/i.test(error.message)) { malas.push(v); continue; }
        else { v.error = C.msg(error); malas.push(v); }
      }
      guardarCola(malas);
      if (ok) {
        if (C.cargarDocumentos) await C.cargarDocumentos();
        await cargarCatalogo(); ventasDeHoy(); tablero(); libroVentas(); render();
        avisar(`${ok} ${ok === 1 ? 'venta sin conexión subió' : 'ventas sin conexión subieron'} a la base${malas.length ? `; ${malas.length} con problema: revisa Modo sin conexión` : ''}`);
      } else if (malas.some(v => v.error)) avisar(`Hay ${malas.length} ${malas.length === 1 ? 'venta' : 'ventas'} sin conexión que no pudieron subir: revisa Modo sin conexión`);
    } finally { subiendo = false; }
  }
  window.addEventListener('online', () => setTimeout(subirCola, 1500));
  setInterval(subirCola, 60000);
  // «Modo sin conexión»: lo que está en la cola de este equipo
  const vOffline = V.offline;
  V.offline = () => { const cola = COLA();
    return `<section class="panel"><div class="hd"><h2>Ventas guardadas en este equipo</h2><span class="pill ${cola.length ? 'warn' : 'ok'}">${cola.length ? cola.length + ' por subir' : 'Todo subido'}</span></div><div class="bd flush tbl-wrap"><table><thead><tr><th>Talonario</th><th>Fecha</th><th>Cliente</th><th class="r">Renglones</th><th>Estado</th></tr></thead><tbody>
      ${cola.map(v => `<tr><td class="num">${FX.F.talSerie}-${p8(v.numero)}</td><td class="num small">${new Date(v.fecha).toLocaleString('es-VE')}</td><td>${C.esc(v.cliente.nombre)}</td><td class="r">${v.items.length}</td><td>${v.error ? `<span class="pill bad">${C.esc(v.error)}</span>` : '<span class="pill warn">Esperando internet</span>'}</td></tr>`).join('') || '<tr><td colspan="5" class="muted">No hay ventas pendientes.</td></tr>'}</tbody></table></div>
      ${cola.length && navigator.onLine ? `<div class="bd"><button class="btn primary" data-act="fr-subir">${ic('sync')}Subir ahora</button></div>` : ''}</section>` + vOffline(); };
  document.addEventListener('click', e => { if (e.target.closest('[data-act="fr-subir"]')) { e.stopImmediatePropagation(); subirCola(); } }, true);
  // Copia local para abrir sin internet
  function guardarCopia() { C.guardarLocal('catalogo', P); C.guardarLocal('clientes', CLIENTS); C.guardarLocal('proveedores', DROG); }

  C.farmacia = {recargar, sincronizar, alCambiarDocs: () => { tablero(); libroVentas(); }};

  /* ---------------- Al entrar ---------------- */
  C.alEntrar(async a => {
    if (a.tipo !== 'farmacia') return;
    // Cada paso por su cuenta: si uno falla, los demás igual cargan (y lo de muestra se vacía)
    const paso = async (n, f) => { try { await f(); } catch (x) { console.error('Cuadre farmacia: ' + n, x); } };
    await paso('catálogo', async () => { try { await cargarCatalogo(); } catch (x) { const c = C.leerLocal('catalogo'); if (!c) throw x; P.length = 0; P.push(...c); c.forEach(marcar); } });
    RECV = []; S.cart = []; S.precioAvisos.length = 0;
    await paso('clientes', async () => { try { await cargarClientes(); } catch (x) { const c = C.leerLocal('clientes'); if (!c) throw x; CLIENTS.length = 0; CLIENTS.push(...c); } });
    ventasDeHoy();
    await paso('proveedores', cargarProveedores);
    await paso('compras', cargarCompras);
    await paso('gastos', cargarGastos);
    await paso('configuración', cargarColecciones);
    await paso('movimientos', cargarMovimientos);
    await paso('resumen', cargarResumen);
    await paso('récipes', cargarRecipes);
    await paso('alertas', cargarAlertas);
    DIF.length = 0;   // el diferencial cambiario necesita los saldos del banco: sin datos de muestra
    if (!EMPLEADOS().some(e => e.id === S.empSel)) S.empSel = EMPLEADOS()[0] ? EMPLEADOS()[0].id : null;
    tablero(); libroVentas();
    if (navigator.onLine) guardarCopia();
    await paso('talonario', siguienteTalonario);
    setTimeout(subirCola, 2000);
  });
})();
