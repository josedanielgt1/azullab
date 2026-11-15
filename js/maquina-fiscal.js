/* =====================================================================
   Cuadre · Máquina fiscal (impresora fiscal) de la farmacia
     * La farmacia factura SOLO por máquina fiscal: sin imprenta digital y
       sin talonario. Mientras el dueño no configure la impresora
       (medio_factura = 'maquina', en Módulo fiscal), la caja no factura.
     * La caja web habla con un AGENTE LOCAL que corre en la computadora
       de la caja y maneja la impresora por USB o serial con la librería
       del fabricante. Protocolo: docs/agente-maquina-fiscal.md.
     * Venta: vender() deja la factura pendiente → el agente la imprime y
       devuelve el número de la memoria fiscal → registrar_maquina().
       Si la impresora falla: reintentar o dejarla pendiente (la falla queda
       en el libro de la máquina); se imprime desde Módulo fiscal.
     * Sin internet: la impresora imprime igual y la venta se guarda en el
       equipo; al volver la conexión sube con vender_impresa(). Si además
       la impresora falla, se reintenta o se cancela la venta.
     * Reporte X y Reporte Z: los imprime la máquina; el Z se guarda en la
       base, que dice si cuadra con sus facturas.
     * Con «simulada» como agente, el equipo imita la impresora (para
       practicar antes de que llegue). Sus números empiezan en 900000001.
   Va después de js/farmacia-real.js.
   ===================================================================== */
(() => {
  const C = window.Cuadre;
  if (!C || !C.listo || C.maquina) return;
  const db = C.db, esc = C.esc;
  const A = () => C.acceso || {};
  const E = () => C.empresa || {};
  const EMP = () => A().empresa_id;
  const activa = () => A().tipo === 'farmacia' && E().medio_factura === 'maquina';   // impresora configurada
  const SIM = 'simulada';
  const simulada = () => E().maquina_agente === SIM;
  const avisar = t => toast(t);
  const r2 = n => Math.round(n * 100) / 100;
  const p8 = n => String(n).padStart(8, '0');
  const p4 = n => String(n).padStart(4, '0');
  const hoyVE = () => new Intl.DateTimeFormat('en-CA', {timeZone: 'America/Caracas'}).format(new Date());
  const cuando = f => new Date(f).toLocaleString('es-VE', {day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false, timeZone: 'America/Caracas'});
  const puedeCaja = () => ['dueno', 'gerente', 'regente', 'cajero'].includes(A().rol);

  /* ---------------- Agente local ---------------- */
  async function pedir(ruta, cuerpo) {
    if (simulada()) return simular(ruta, cuerpo);
    const base = String(E().maquina_agente || 'http://127.0.0.1:7123').replace(/\/$/, '');
    const ctl = new AbortController(), reloj = setTimeout(() => ctl.abort(), ruta === '/estado' ? 4000 : 45000);
    try {
      const r = await fetch(base + ruta, {method: cuerpo ? 'POST' : 'GET', signal: ctl.signal,
        headers: cuerpo ? {'content-type': 'application/json'} : {}, body: cuerpo ? JSON.stringify(cuerpo) : undefined});
      const j = await r.json().catch(() => null);
      if (!j || typeof j !== 'object') return {ok: false, error: 'El agente de la impresora respondió algo que no se entiende'};
      if (!r.ok && j.ok !== false) return {ok: false, error: 'El agente de la impresora respondió con el error ' + r.status};
      return j;
    } catch (x) {
      return {ok: false, error: x.name === 'AbortError' ? 'La impresora tardó demasiado en responder'
        : 'No hay comunicación con el agente de la impresora en esta computadora'};
    } finally { clearTimeout(reloj); }
  }

  /* Impresora simulada: guarda sus contadores en este equipo */
  function simular(ruta, c) {
    const reg = E().maquina_registro;
    const s = C.leerLocal('maquina_sim') || {FAC: 900000000, NC: 900000000, ND: 900000000, z: 9000, impresos: {}, j: null};
    const vacia = () => ({FAC: [], NC: [], ND: [], exento: 0, base_general: 0, iva_general: 0, base_reducida: 0, iva_reducida: 0, total: 0});
    s.j = s.j || vacia();
    const resumen = () => { const rango = k => s.j[k].length ? [Math.min(...s.j[k]), Math.max(...s.j[k])] : [null, null];
      const [fd, fh] = rango('FAC'), [cd, ch] = rango('NC'), [dd, dh] = rango('ND');
      return {fac_desde: fd, fac_hasta: fh, cant_fac: s.j.FAC.length, nc_desde: cd, nc_hasta: ch, cant_nc: s.j.NC.length, nd_desde: dd, nd_hasta: dh, cant_nd: s.j.ND.length,
        exento: r2(s.j.exento), base_general: r2(s.j.base_general), iva_general: r2(s.j.iva_general), base_reducida: r2(s.j.base_reducida), iva_reducida: r2(s.j.iva_reducida), total: r2(s.j.total)}; };
    const guardar = () => C.guardarLocal('maquina_sim', s);
    if (ruta === '/estado') return {ok: true, registro: reg, modelo: 'Simulada', simulada: true};
    if (ruta === '/documento') {
      if (s.impresos[c.id]) return {ok: true, numero: s.impresos[c.id], registro: reg, fecha: new Date().toISOString(), simulada: true, repetida: true};
      const n = ++s[c.tipo]; s.impresos[c.id] = n; s.j[c.tipo].push(n);
      const sg = c.tipo === 'NC' ? -1 : 1, t = c.totales || {};
      ['exento', 'base_general', 'iva_general', 'base_reducida', 'iva_reducida', 'total'].forEach(k => { s.j[k] += sg * (+t[k] || 0); });
      guardar();
      return {ok: true, numero: n, registro: reg, fecha: new Date().toISOString(), simulada: true};
    }
    if (ruta === '/reporte-x') return {ok: true, registro: reg, simulada: true, ...resumen()};
    if (ruta === '/reporte-z') { const z = {ok: true, registro: reg, simulada: true, numero: ++s.z, ...resumen()}; s.j = vacia(); guardar(); return z; }
    return {ok: false, error: 'La impresora simulada no conoce ' + ruta};
  }

  /* ---------------- Estado de la impresora (MAQ lo pinta la página) ---------------- */
  function ponerDatos() {
    if (typeof MAQ !== 'object') return;
    const e = E();
    MAQ.modelo = [e.maquina_marca, e.maquina_modelo].filter(Boolean).join(' ') || 'Impresora fiscal';
    MAQ.corto = simulada() ? 'Impresora simulada' : (e.maquina_modelo || 'Impresora');
    MAQ.registro = e.maquina_registro || '—';
    MAQ.conexion = simulada() ? 'Simulada en este equipo (no es fiscal)' : 'Agente local en esta computadora';
    if (MAQ.ultFac === undefined || MAQ.ultFac === null) MAQ.ultFac = 0;
    if (MAQ.ultZ === undefined || MAQ.ultZ === null) MAQ.ultZ = false;
    MAQ.memoria = MAQ.memoria === '4% usada' ? null : MAQ.memoria;
  }
  function marcar(lista, error) {
    if (typeof MAQ !== 'object') return;
    MAQ.lista = lista;
    MAQ.estado = lista ? (simulada() ? 'Simulada' : 'Conectada') : 'Sin comunicación';
    MAQ.error = error || '';
  }
  async function revisarEstado() {
    if (!activa()) return;
    const r = await pedir('/estado');
    const antes = MAQ.lista;
    marcar(!!r.ok, r.error);
    if (r.ok && r.memoria) MAQ.memoria = r.memoria;
    if (r.ok && r.registro && E().maquina_registro && String(r.registro).toUpperCase() !== E().maquina_registro) {
      marcar(false, `La impresora conectada es la ${r.registro} y este negocio tiene registrada la ${E().maquina_registro}`);
    }
    if (antes !== MAQ.lista && S.view !== 'login') render();
  }

  /* ---------------- Lo que la pantalla necesita de la base ---------------- */
  let pendientes = [], zs = [], eventos = [], zHoy = null;
  async function refrescar() {
    if (!activa()) return;
    const [{data: pe}, {data: z}, {data: ev}, {data: uf}] = await Promise.all([
      db.from('documentos').select('id,tipo,numero,cliente_nombre,total,fecha').eq('empresa_id', EMP()).eq('medio', 'maquina').eq('estado', 'pendiente_imprenta').order('fecha'),
      db.from('reportes_z').select('*').eq('empresa_id', EMP()).order('numero', {ascending: false}).limit(10),
      db.from('maquina_eventos').select('*').eq('empresa_id', EMP()).order('id', {ascending: false}).limit(30),
      db.from('documentos').select('numero_fiscal').eq('empresa_id', EMP()).eq('medio', 'maquina').eq('tipo', 'FAC').eq('maquina_registro', E().maquina_registro || '').order('numero_fiscal', {ascending: false, nullsFirst: false}).limit(1)]);
    const lista = x => Array.isArray(x) ? x : [];
    pendientes = lista(pe); zs = lista(z); eventos = lista(ev);
    zHoy = zs.find(x => x.dia === hoyVE() && x.maquina_registro === E().maquina_registro) || null;
    if (typeof MAQ === 'object') {
      MAQ.ultFac = uf && uf[0] && uf[0].numero_fiscal ? +uf[0].numero_fiscal : 0;
      const u = zs.find(x => x.maquina_registro === E().maquina_registro);
      MAQ.ultZ = u ? {numero: u.numero, cuando: cuando(u.fecha)} : false;
    }
  }

  /* ---------------- Lo que se le manda a la impresora ---------------- */
  async function documentoCompleto(id) {
    const {data, error} = await db.from('documentos').select('*, documento_lineas(*), documento_pagos(*)').eq('id', id).single();
    if (error) throw error;
    return data;
  }
  function carga(d, af) {
    return {id: d.id, tipo: d.tipo, fecha: d.fecha,
      cliente: {rif: d.cliente_rif, nombre: d.cliente_nombre, dir: d.cliente_dir || null, tel: d.cliente_tel || null},
      lineas: (d.documento_lineas || []).sort((a, b) => a.renglon - b.renglon)
        .map(l => ({descripcion: l.descripcion, cantidad: +l.cantidad, precio: +l.precio_unit, alicuota: l.alicuota})),
      pagos: (d.documento_pagos || []).map(p => ({metodo: p.metodo, monto: +p.monto_bs})),
      totales: {exento: +d.base_exenta, base_general: +d.base_general, iva_general: +d.iva_general,
        base_reducida: +d.base_reducida, iva_reducida: +d.iva_reducida, igtf: +d.igtf, total: +d.total},
      tasa: +d.tasa, total_usd: +d.total_usd, motivo: d.motivo || null,
      afecta: af ? {numero: af.numero_fiscal || null, control: af.numero_control || null, fecha: af.fecha, registro: af.maquina_registro || null} : null,
      pie: ['REF. USD ' + nf(+d.total_usd), 'TASA BCV ' + nf(+d.tasa)]};
  }

  /* ---------------- Cuando la impresora no imprime ---------------- */
  let resolver = null;
  // conPendiente: con internet la venta ya está en la base y puede quedar pendiente de imprimir.
  // Sin internet no hay dónde dejarla: se reintenta o se cancela la venta.
  function preguntarFalla(error, conPendiente) {
    return new Promise(res => {
      resolver = res;
      openModal(`<div class="sheet" role="dialog" aria-modal="true" aria-labelledby="mq-t" style="max-width:460px"><div class="hd"><h2 id="mq-t">La impresora no imprimió</h2></div><div class="bd">
        <p class="fx-aviso" style="margin:0">${ic('alert')}<span>${esc(error)}</span></p>
        <p class="small" style="margin:0">Revisa que esté encendida, con papel y la tapa cerrada, y reintenta. ${conPendiente
          ? 'Si está dañada, deja la factura <b>pendiente</b>: queda anotada la falla en el libro de la máquina y se imprime desde Módulo fiscal cuando la impresora vuelva. Llama al servicio técnico autorizado.'
          : 'Sin internet y sin impresora no se puede facturar: reintenta o cancela la venta (el carrito queda como estaba).'}</p>
        ${conPendiente ? `<div class="field"><label for="mq-mot">Qué le pasó a la impresora</label><input id="mq-mot" class="input" value="${esc(String(error).slice(0, 120))}"></div>` : ''}
        <div class="row">${conPendiente ? '<button class="btn" data-act="mq-pend">Dejar pendiente</button>' : '<button class="btn" data-act="mq-pend">Cancelar la venta</button>'}<span class="spacer"></span><button class="btn primary" data-act="mq-reint">Reintentar</button></div></div></div>`);
    });
  }
  document.addEventListener('click', e => {
    const b = e.target.closest('[data-act="mq-pend"],[data-act="mq-reint"]'); if (!b || !resolver) return;
    e.preventDefault(); e.stopImmediatePropagation();
    const res = resolver, act = b.dataset.act;
    const motivo = ((document.getElementById('mq-mot') || {}).value || '').trim();
    resolver = null; closeModal(); res(act === 'mq-reint' ? 'reintentar' : {pendiente: true, motivo});
  }, true);

  /* ---------------- Imprimir una factura o nota que ya está en la base ---------------- */
  async function imprimir(doc, conPendiente = true) {
    let d, af = null;
    try {
      d = await documentoCompleto(doc.id);
      if (d.afecta_id) { const {data} = await db.from('documentos').select('numero_fiscal,numero_control,fecha,maquina_registro').eq('id', d.afecta_id).single(); af = data; }
    } catch (x) { avisar('No se pudo leer la factura para imprimirla: ' + C.msg(x)); return doc; }
    for (;;) {
      const r = await pedir('/documento', carga(d, af));
      if (r.ok) {
        marcar(true);
        const resp = {...r}; delete resp.ok; delete resp.texto;
        const {data, error} = await db.rpc('registrar_maquina', {p_doc: d.id, p_numero: r.numero, p_registro: r.registro || E().maquina_registro, p_resp: resp});
        if (error) {
          avisar(`La impresora imprimió el número ${r.numero}, pero la base no lo aceptó: ${C.msg(error)}. Guarda el ticket y avisa a Cuadre.`);
          C.maquina.alCambiar(); return doc;
        }
        if (d.tipo === 'FAC' && typeof MAQ === 'object') MAQ.ultFac = Math.max(+MAQ.ultFac || 0, +r.numero);
        C.maquina.alCambiar(); return data;
      }
      marcar(false, r.error);
      const ele = await preguntarFalla(r.error || 'La impresora no respondió', conPendiente);
      if (ele === 'reintentar') continue;
      // Queda pendiente de imprimir; la falla se anota en el libro de control de la máquina
      try { await db.from('maquina_eventos').insert({empresa_id: EMP(), maquina_registro: E().maquina_registro, tipo: 'falla',
        detalle: (ele.motivo || r.error || 'La impresora no imprimió') + ' · ' + (d.tipo === 'FAC' ? 'venta' : 'nota') + ' P-' + p8(d.numero) + ' quedó pendiente'}); } catch (_) {}
      avisar('Quedó pendiente de imprimir: la ves en Módulo fiscal. Llama al servicio técnico autorizado');
      C.maquina.alCambiar(); return doc;
    }
  }

  /* ---------------- Sin internet: la impresora imprime igual ---------------- */
  async function ventaSinInternet() {
    const rate = S.rate, iva = +(E().iva_general ?? 16), ivr = +(E().iva_reducida ?? 8);
    const items = S.cart.flatMap(c => { const p = P.find(x => x.id === c.id); return segs(p, c.q).map(sg => ({p, cantidad: sg.q, precio_usd: sg.pv ?? p.price})); });
    const cli = S.client ? {rif: S.client.ci, nombre: S.client.name, tel: S.client.tel && S.client.tel !== '—' ? S.client.tel : null} : {rif: 'V-00000000', nombre: 'Consumidor final'};
    const pagos = S.pays.map(p => ({metodo: p.k, monto_bs: r2(p.a * rate), divisa: !!p.div}));
    const lineas = items.map(i => { const pu = r2(i.precio_usd * rate); return {descripcion: i.p.name + (i.p.pres && i.p.pres !== '—' ? ' · ' + i.p.pres : ''), cantidad: i.cantidad, precio: pu, alicuota: i.p.iva}; });
    const t = {exento: 0, base_general: 0, base_reducida: 0};
    lineas.forEach(l => { const m = r2(l.precio * l.cantidad); if (l.alicuota === 'G') t.base_general += m; else if (l.alicuota === 'R') t.base_reducida += m; else t.exento += m; });
    t.iva_general = r2(t.base_general * iva / 100); t.iva_reducida = r2(t.base_reducida * ivr / 100); t.igtf = 0;
    t.total = r2(t.exento + t.base_general + t.iva_general + t.base_reducida + t.iva_reducida);
    const id = (crypto.randomUUID ? crypto.randomUUID() : 'v' + Date.now() + Math.random().toString(16).slice(2));
    const fecha = new Date().toISOString();
    for (;;) {
      const r = await pedir('/documento', {id, tipo: 'FAC', fecha, cliente: cli, lineas, pagos: pagos.map(p => ({metodo: p.metodo, monto: p.monto_bs})),
        totales: t, tasa: rate, total_usd: r2(t.total / rate), motivo: null, afecta: null, pie: ['REF. USD ' + nf(r2(t.total / rate)), 'TASA BCV ' + nf(rate)]});
      if (r.ok) {
        marcar(true);
        const resp = {...r}; delete resp.ok; delete resp.texto;
        const cola = C.leerLocal('cola') || [];
        cola.push({numero: +r.numero, maquina: String(r.registro || E().maquina_registro).toUpperCase(), fecha: r.fecha || fecha, cliente: cli,
          items: items.map(i => ({producto_id: i.p.id, cantidad: i.cantidad, precio_usd: i.precio_usd})), pagos, usuario: A().nombre, resp});
        C.guardarLocal('cola', cola);
        if (typeof MAQ === 'object') MAQ.ultFac = Math.max(+MAQ.ultFac || 0, +r.numero);
        return {medio: 'maquina', numero_fiscal: +r.numero, maquina_registro: String(r.registro || E().maquina_registro).toUpperCase(), numero: null, id: null};
      }
      marcar(false, r.error);
      const ele = await preguntarFalla(r.error || 'La impresora no respondió', false);
      if (ele === 'reintentar') continue;
      avisar('Venta cancelada: no se facturó. El carrito sigue igual');
      return null;   // sin internet y sin impresora no se factura
    }
  }

  /* ---------------- Reporte X y Reporte Z ---------------- */
  const hoja = (tit, cuerpo) => `<div class="sheet" role="dialog" aria-modal="true" style="max-width:480px"><div class="hd"><h2>${tit}</h2><button class="x" data-act="close" aria-label="Cerrar">${ic('x')}</button></div><div class="bd">${cuerpo}</div></div>`;
  const filaCmp = (k, maq, sis, bs) => { const ig = maq == null || sis == null ? null : Math.abs(+maq - +sis) < (bs ? 0.05 : 0.5);
    return `<tr><td>${k}</td><td class="r">${maq == null ? '—' : bs ? nf(+maq) : maq}</td><td class="r">${sis == null ? '—' : bs ? nf(+sis) : sis}</td><td>${ig == null ? '' : `<span class="pill ${ig ? 'ok' : 'warn'}">${ig ? 'Igual' : 'Distinto'}</span>`}</td></tr>`; };
  const tablaCmp = (m, s) => `<div class="tbl-wrap"><table><thead><tr><th></th><th class="r">Impresora</th><th class="r">Cuadre</th><th></th></tr></thead><tbody>
    ${filaCmp('Facturas', m.cant_fac, s.cant_fac)}${filaCmp('Notas de crédito', m.cant_nc, s.cant_nc)}
    ${filaCmp('Exento Bs', m.exento, s.exento, true)}${filaCmp('Base 16 % Bs', m.base_general, s.base_general, true)}${filaCmp('IVA 16 % Bs', m.iva_general, s.iva_general, true)}
    ${filaCmp('Total neto Bs', m.total, s.total, true)}</tbody></table></div>`;
  async function jornada() { if (!navigator.onLine) return null; const {data, error} = await db.rpc('jornada_maquina', {p_empresa: EMP()}); if (error) throw error; return data; }

  async function reporteX() {
    const [r, j] = await Promise.all([pedir('/reporte-x', {}), jornada().catch(() => null)]);
    if (!r.ok) marcar(false, r.error);
    openModal(hoja('Reporte X', `<p class="small muted" style="margin:0">Lectura de lo vendido hoy, sin cerrar la jornada.</p>
      ${r.ok ? '' : `<p class="fx-aviso" style="margin:0">${ic('alert')}<span>${esc(r.error)}</span></p>`}
      ${j ? tablaCmp(r.ok ? r : {}, j) : '<p class="small muted">Sin internet: solo se ve lo que dice la impresora.</p>'}
      ${j && j.pendientes ? `<p class="fx-aviso" style="margin:0">${ic('alert')}<span>Hay ${j.pendientes} ${j.pendientes === 1 ? 'factura pendiente' : 'facturas pendientes'} de imprimir. Resuélvelas en Módulo fiscal antes del Reporte Z.</span></p>` : ''}
      ${r.texto ? `<div class="tkwrap"><pre class="ticket">${esc(r.texto)}</pre></div>` : ''}
      <button class="btn" data-act="close">Listo</button>`));
  }
  async function reporteZ() {
    if (!puedeCaja()) { avisar('Tu usuario no hace el Reporte Z'); return; }
    const local = C.leerLocal('z_pendiente');
    if (local) { avisar(`El Reporte Z N.° ${p4(local.numero)} se hizo sin internet y está por subir`); return; }
    if (navigator.onLine) await refrescar().catch(() => {});
    if (zHoy) { avisar(`El Reporte Z de hoy ya se hizo: N.° ${p4(zHoy.numero)} a las ${cuando(zHoy.fecha).slice(-5)}`); return; }
    const j = await jornada().catch(() => null);
    openModal(hoja('Cierre del día', `<p style="margin:0">El Reporte Z cierra la jornada en la memoria fiscal de la impresora. Se hace <b>una vez al día</b>; las ventas siguientes cuentan para mañana.</p>
      ${j && j.pendientes ? `<p class="fx-aviso" style="margin:0">${ic('alert')}<span>Hay ${j.pendientes} ${j.pendientes === 1 ? 'factura pendiente' : 'facturas pendientes'} de imprimir: resuélvelas primero en Módulo fiscal o el Z no va a cuadrar.</span></p>` : ''}
      ${j ? `<p class="small muted" style="margin:0">Según Cuadre: ${j.cant_fac} facturas, ${j.cant_nc} notas de crédito, total neto Bs ${nf(+j.total)}.</p>` : ''}
      <div class="row"><button class="btn" style="flex:1" data-act="close">Cancelar</button><button class="btn primary" style="flex:1" data-act="mq-zgo">Hacer Reporte Z</button></div>`));
  }
  async function hacerZ(b) {
    b.disabled = true; b.textContent = 'Imprimiendo…';
    const r = await pedir('/reporte-z', {});
    if (!r.ok) { marcar(false, r.error); closeModal(); avisar('La impresora no hizo el Reporte Z: ' + r.error); return; }
    marcar(true);
    const z = {...r}; delete z.ok; delete z.texto;
    if (!navigator.onLine) {
      C.guardarLocal('z_pendiente', {...z, fecha: new Date().toISOString(), registro: r.registro || E().maquina_registro});
      openModal(hoja(`Reporte Z N.° ${p4(r.numero)} impreso`, `<p class="envio">${ic('clock')}Sin internet: se guarda en este equipo y sube solo al volver la conexión.</p>
        ${r.texto ? `<div class="tkwrap"><pre class="ticket">${esc(r.texto)}</pre></div>` : ''}<button class="btn" data-act="close">Listo</button>`));
      return;
    }
    await subirZ(z, r.registro || E().maquina_registro, r.texto);
  }
  async function subirZ(z, registro, texto) {
    const {data, error} = await db.rpc('registrar_reporte_z', {p_empresa: EMP(), p_registro: registro, p_z: z});
    if (error) {
      C.guardarLocal('z_pendiente', {...z, fecha: z.fecha || new Date().toISOString(), registro, error: C.msg(error)});
      avisar('La impresora hizo el Reporte Z, pero la base no lo aceptó: ' + C.msg(error)); return false;
    }
    C.guardarLocal('z_pendiente', null);
    await refrescar().catch(() => {});
    if (C.cargarDocumentos) await C.cargarDocumentos().catch(() => {});
    if (C.farmacia && C.farmacia.alCambiarDocs) C.farmacia.alCambiarDocs();
    openModal(hoja(`Reporte Z N.° ${p4(data.numero)}`, `<p class="envio">${data.cuadra ? ic('check') + 'Cuadra con las facturas de Cuadre' : ic('alert') + 'No cuadra con las facturas de Cuadre'}
        <span class="pill ${data.cuadra ? 'ok' : 'warn'}">${data.cuadra ? 'Cuadra' : 'Revisar'}</span></p>
      ${tablaCmp(data, {cant_fac: data.sis_cant_fac, cant_nc: data.sis_cant_nc, total: data.sis_total})}
      ${data.cuadra ? '' : '<p class="small" style="margin:0">Puede faltar una factura pendiente de imprimir o una venta sin internet que todavía no subió. Si no se resuelve, avisa a Cuadre con el ticket del Z.</p>'}
      ${texto ? `<div class="tkwrap"><pre class="ticket">${esc(texto)}</pre><span class="sello tk-sello estampar">Cierre fiscal<small>Z ${p4(data.numero)}</small></span></div>` : ''}
      <button class="btn" data-act="close">Listo</button>`));
    render();
    return true;
  }
  async function subirZPendiente() {
    const z = C.leerLocal('z_pendiente');
    if (!z || !navigator.onLine || !activa() || z.error) return;
    const {registro, ...datos} = z;
    const {error} = await db.rpc('registrar_reporte_z', {p_empresa: EMP(), p_registro: registro, p_z: datos});
    if (error) { C.guardarLocal('z_pendiente', {...z, error: C.msg(error)}); return; }
    C.guardarLocal('z_pendiente', null); await refrescar().catch(() => {}); avisar(`El Reporte Z N.° ${p4(z.numero)} hecho sin internet ya subió`);
  }
  window.addEventListener('online', () => setTimeout(subirZPendiente, 4000));

  document.addEventListener('click', e => {
    const b = e.target.closest('[data-act="repx"],[data-act="repz"],[data-act="dozz"],[data-act="mq-zgo"]');
    if (!b || !activa()) return;
    e.preventDefault(); e.stopImmediatePropagation();
    const act = b.dataset.act;
    (act === 'repx' ? reporteX() : act === 'mq-zgo' ? hacerZ(b) : reporteZ()).catch(x => avisar(C.msg(x)));
  }, true);

  /* ---------------- Ticket ---------------- */
  if (typeof window.ticketText === 'function') {
    const ticketOriginal = window.ticketText;
    window.ticketText = function (sale) {
      if (!activa() || sale.mode !== 'maquina') return ticketOriginal(sale);
      const d = sale.doc ? FX.byId(sale.doc) : null;
      let txt = ticketOriginal(sale);
      if (d && /^P-/.test(d.num)) txt = txt.replace('SENIAT', 'PENDIENTE DE IMPRIMIR').replace('FACTURA N:', 'VENTA N:  ');
      if (simulada()) txt = txt.replace(/^.*MH .*$/m, ctr('IMPRESORA SIMULADA') + '\n' + ctr('NO ES UNA FACTURA FISCAL'));
      return txt;
    };
  }
  if (typeof window.ticketModal === 'function') {
    const modalOriginal = window.ticketModal;
    window.ticketModal = function (sale) {
      let h = modalOriginal(sale);
      if (!activa() || sale.mode !== 'maquina') return h;
      const d = sale.doc ? FX.byId(sale.doc) : null;
      if (d && /^P-/.test(d.num)) h = h.replace(/<p class="small muted" style="text-align:center">[\s\S]*?<\/p>/, `<p class="envio">${ic('clock')}La impresora no la imprimió <span class="pill warn">Pendiente</span></p>`);
      return h;
    };
  }

  /* ---------------- Libro de ventas con máquina fiscal ----------------
     Reglamento de la Ley del IVA, art. 77: las facturas a consumidor final van resumidas por Reporte Z,
     del primer al último número, con el registro de la máquina. Las de RIF y las notas
     van una por una (eso lo hace el motor fiscal común). Las que la impresora aún no imprimió se listan aparte. */
  if (typeof FX === 'object' && typeof FX.libroVentas === 'function') {
    const libroComun = FX.libroVentas;
    const conRif = id => /^[JGVEPC]-\d{8}-\d$/.test(String(id || '').replace(/\./g, '').toUpperCase());
    FX.libroVentas = () => {
      if (!activa()) return libroComun();
      const mes = (FX.Y && FX.Y.hoy ? FX.Y.hoy : hoyVE()).slice(0, 7);
      const resumida = d => d.medio === 'maquina' && d.tipo === 'FAC' && !conRif(d.cli.id);
      const todos = FX.docs.slice(), quedan = todos.filter(d => !resumida(d));
      let rows;
      FX.docs.length = 0; FX.docs.push(...quedan);
      try { rows = libroComun(); } finally { FX.docs.length = 0; FX.docs.push(...todos); }
      const grupos = {};
      todos.filter(d => resumida(d) && d.fecha.startsWith(mes)).forEach(d => {
        const pend = !/^\d+$/.test(String(d.num)), k = pend ? 'P|' + d.fecha : d.z ? 'Z|' + d.z : 'A|' + d.fecha;
        const g = grupos[k] = grupos[k] || {fecha: d.fecha, z: d.z, pend, reg: d.reg, n: 0, lo: Infinity, hi: 0, ex: 0, bg: 0, ivg: 0, br: 0, ivr: 0, total: 0};
        const t = d.t, n = pend ? 0 : +d.num;
        g.n++; if (!pend) { g.lo = Math.min(g.lo, n); g.hi = Math.max(g.hi, n); }
        g.fecha = d.fecha < g.fecha ? d.fecha : g.fecha;
        g.ex = r2(g.ex + t.ex); g.bg = r2(g.bg + t.bg); g.ivg = r2(g.ivg + t.ivg); g.br = r2(g.br + t.br); g.ivr = r2(g.ivr + t.ivr); g.total = r2(g.total + t.total - t.igtf);
      });
      Object.values(grupos).forEach(g => rows.push({fecha: g.fecha, kind: 'cf', tipo: 'FAC',
        num: g.pend ? '—' : g.n > 1 ? `${p8(g.lo)} al ${p8(g.hi)}` : p8(g.lo), ctrl: g.reg ? 'MH ' + g.reg : '', afecta: '', rif: '',
        nombre: g.pend ? `Consumidor final · ${g.n} pendientes de imprimir` : g.z ? `Consumidor final · Reporte Z N.° ${p4(g.z)} · ${g.n} ${g.n === 1 ? 'factura' : 'facturas'}` : `Consumidor final · ${g.n} ${g.n === 1 ? 'factura' : 'facturas'} (falta el Reporte Z)`,
        ex: g.ex, bg: g.bg, ivg: g.ivg, br: g.br, ivr: g.ivr, total: g.total, ret: 0, comp: '', igtf: 0, key: g.pend ? 4e8 : g.lo}));
      rows.sort((a, b) => a.fecha.localeCompare(b.fecha) || a.key - b.key);
      rows.forEach((r, i) => { r.op = i + 1; });
      return rows;
    };
  }

  /* ---------------- Módulo fiscal: pendientes, Reportes Z, libro de la máquina y configuración ---------------- */
  const TIPOS_EV = {instalacion: 'Instalación', inspeccion: 'Inspección', reparacion: 'Reparación', falla: 'Falla', 'cambio de precinto': 'Cambio de precinto', otro: 'Otro'};
  const vFiscal = V.fiscal;
  V.fiscal = () => {
    const base = vFiscal();
    if (A().tipo === 'farmacia' && !activa()) return sinImpresora();
    if (!activa()) return base;
    const dueno = A().rol === 'dueno';
    const zLocal = C.leerLocal('z_pendiente');
    return (simulada() ? `<p class="fx-aviso" style="margin:0 0 12px">${ic('alert')}<span><b>Impresora simulada.</b> Sirve para practicar: lo que se factura así no es fiscal. Cámbiala por la real en «Configurar la impresora» cuando esté instalada.</span></p>` : '')
      + (MAQ.lista === false && MAQ.error ? `<p class="fx-aviso" style="margin:0 0 12px">${ic('alert')}<span>${esc(MAQ.error)}</span></p>` : '')
      + base + `
    <section class="panel"><div class="hd"><h2>Pendientes de imprimir</h2><span class="pill ${pendientes.length ? 'warn' : 'ok'}">${pendientes.length ? pendientes.length + ' pendientes' : 'Ninguna'}</span></div>
      <div class="bd flush tbl-wrap"><table><thead><tr><th>Documento</th><th>Fecha</th><th>Cliente</th><th class="r">Total Bs</th><th></th></tr></thead><tbody>
      ${pendientes.map(p => `<tr><td class="num">${p.tipo === 'FAC' ? 'Venta' : p.tipo === 'NC' ? 'Nota de crédito' : 'Nota de débito'} P-${p8(p.numero)}</td><td class="num small">${cuando(p.fecha)}</td><td>${esc(p.cliente_nombre)}</td><td class="r">${nf(+p.total)}</td>
        <td class="r">${puedeCaja() ? `<button class="btn sm" data-act="mq-repend" data-id="${esc(p.id)}">${ic('printer')}Imprimir</button>` : ''}</td></tr>`).join('') || '<tr><td colspan="5" class="muted">Todo lo vendido quedó impreso.</td></tr>'}</tbody></table></div>
      <div class="bd small muted" style="border-top:1px solid var(--line)">Si la impresora sigue dañada, llama al servicio técnico autorizado y anota la falla en el libro de la máquina. Cuando la reparen, imprime aquí lo pendiente.</div></section>
    <section class="panel"><div class="hd"><h2>Reportes Z</h2>${zLocal ? `<span class="pill warn">Z ${p4(zLocal.numero)} por subir${zLocal.error ? ': ' + esc(zLocal.error) : ''}</span>` : ''}</div>
      <div class="bd flush tbl-wrap"><table><thead><tr><th>Z</th><th>Día</th><th class="r">Facturas</th><th class="r">Total Bs (impresora)</th><th class="r">Total Bs (Cuadre)</th><th></th></tr></thead><tbody>
      ${zs.map(z => `<tr><td class="num">${p4(z.numero)}</td><td class="num small">${z.dia.split('-').reverse().join('/')}</td><td class="r">${z.cant_fac}</td><td class="r">${nf(+z.total)}</td><td class="r">${z.sis_total == null ? '—' : nf(+z.sis_total)}</td>
        <td><span class="pill ${z.cuadra ? 'ok' : 'warn'}">${z.cuadra ? 'Cuadra' : 'Revisar'}</span></td></tr>`).join('') || '<tr><td colspan="6" class="muted">Todavía no hay Reportes Z.</td></tr>'}</tbody></table></div></section>
    <section class="panel"><div class="hd"><h2>Libro de control de la máquina</h2><span class="muted small">Instalación, inspecciones, fallas y reparaciones</span></div>
      <div class="bd flush tbl-wrap"><table><thead><tr><th>Fecha</th><th>Tipo</th><th>Detalle</th><th>Técnico</th></tr></thead><tbody>
      ${eventos.map(v => `<tr><td class="num small">${v.fecha.split('-').reverse().join('/')}</td><td>${TIPOS_EV[v.tipo] || esc(v.tipo)}</td><td>${esc(v.detalle)}</td><td>${esc(v.tecnico || '—')}</td></tr>`).join('') || '<tr><td colspan="4" class="muted">Sin anotaciones.</td></tr>'}</tbody></table></div>
      ${puedeCaja() ? `<div class="bd" style="border-top:1px solid var(--line)"><form id="mq-ev" class="grid g2" style="gap:8px 14px">
        <div class="field"><label for="mq-ev-t">Tipo</label><select id="mq-ev-t" class="input">${Object.entries(TIPOS_EV).map(([k, t]) => `<option value="${k}">${t}</option>`).join('')}</select></div>
        <div class="field"><label for="mq-ev-tec">Técnico (si vino)</label><input id="mq-ev-tec" class="input" maxlength="80"></div>
        <div class="field" style="grid-column:1/-1"><label for="mq-ev-d">Detalle</label><input id="mq-ev-d" class="input" maxlength="300" placeholder="Qué pasó o qué se hizo"></div>
        <div class="row" style="grid-column:1/-1"><span class="small muted">Lo anotado no se edita ni se borra. El libro físico sigue junto a la máquina.</span><span class="spacer"></span><button class="btn" type="submit">Anotar</button></div></form></div>` : ''}</section>
    ${dueno ? `<section class="panel"><div class="hd"><h2>Configurar la impresora</h2></div><div class="bd"><button class="btn" data-act="medio">${ic('printer')}Cambiar los datos de la impresora fiscal</button></div></section>` : ''}`;
  };
  // Sin la impresora configurada, la farmacia no factura: el Módulo fiscal lo dice primero
  const sinImpresora = () => `<p class="fx-aviso" style="margin:0 0 12px">${ic('alert')}<span><b>Falta configurar la impresora fiscal.</b> La farmacia factura solo por máquina fiscal: mientras no esté configurada, la caja no emite facturas.${A().rol === 'dueno' ? '' : ' Avísale al dueño.'}</span></p>`
    + (A().rol === 'dueno' ? `<section class="panel"><div class="hd"><h2>Impresora fiscal</h2><span class="pill warn">Sin configurar</span></div><div class="bd"><button class="btn primary" data-act="medio">${ic('printer')}Configurar la impresora fiscal</button>
      <p class="small muted" style="margin:10px 0 0">Marca, modelo, número de registro (junto al logo MH) y el agente de la computadora de la caja. Para practicar sin impresora, escribe «simulada» como agente.</p></div></section>` : '');
  document.addEventListener('click', e => {
    const b = e.target.closest('[data-act="mq-repend"]'); if (!b || !activa()) return;
    e.preventDefault(); e.stopImmediatePropagation();
    if (!navigator.onLine) { avisar('Hace falta internet para imprimir una factura pendiente'); return; }
    b.disabled = true;
    imprimir({id: b.dataset.id}).then(async () => { if (C.cargarDocumentos) await C.cargarDocumentos(); if (C.farmacia && C.farmacia.alCambiarDocs) C.farmacia.alCambiarDocs(); await refrescar(); render(); })
      .catch(x => avisar(C.msg(x))).finally(() => { b.disabled = false; });
  }, true);
  document.addEventListener('submit', async e => {
    if (e.target.id !== 'mq-ev' || !activa()) return;
    e.preventDefault(); e.stopImmediatePropagation();
    const f = e.target, detalle = f.querySelector('#mq-ev-d').value.trim(), tecnico = f.querySelector('#mq-ev-tec').value.trim();
    if (!detalle) { avisar('Escribe el detalle'); return; }
    const {error} = await db.from('maquina_eventos').insert({empresa_id: EMP(), maquina_registro: E().maquina_registro, tipo: f.querySelector('#mq-ev-t').value, detalle, tecnico: tecnico || null});
    if (error) { avisar(C.msg(error)); return; }
    avisar('Anotado en el libro de la máquina'); await refrescar(); render();
  }, true);

  /* Datos de la impresora fiscal: solo el dueño. La farmacia no tiene otro medio de facturación */
  function configHtml() {
    const e = E();
    const v = x => esc(x || '');
    return hoja('Impresora fiscal', `
      <p class="small muted" style="margin:0">La farmacia factura solo por máquina fiscal. Estos datos están en la placa de la impresora y en su libro de control.</p>
      <div class="grid g2" style="gap:8px 14px">
        <div class="field"><label for="mq-marca">Marca</label><input id="mq-marca" class="input" value="${v(e.maquina_marca)}" placeholder="The Factory"></div>
        <div class="field"><label for="mq-modelo">Modelo</label><input id="mq-modelo" class="input" value="${v(e.maquina_modelo)}" placeholder="HKA80"></div>
        <div class="field"><label for="mq-reg">Número de registro (junto al logo MH)</label><input id="mq-reg" class="input num" value="${v(e.maquina_registro)}" placeholder="Z7C0012345"></div>
        <div class="field"><label for="mq-dist">Distribuidor o servicio técnico</label><input id="mq-dist" class="input" value="${v(e.maquina_distribuidor)}"></div>
        <div class="field" style="grid-column:1/-1"><label for="mq-ag">Agente de la impresora</label><input id="mq-ag" class="input num" value="${v(e.maquina_agente || 'http://127.0.0.1:7123')}">
          <span class="small muted">Lo deja instalado Cuadre en la computadora de la caja. Escribe <b>simulada</b> para practicar sin impresora (no es fiscal).</span></div></div>
      <div class="row"><button class="btn" style="flex:1" data-act="close">Cancelar</button><button class="btn primary" style="flex:1" data-act="mq-cfg">Guardar</button></div>`);
  }
  document.addEventListener('click', e => {
    const b = e.target.closest('[data-act="medio"]'); if (!b || !C.acceso || A().tipo !== 'farmacia') return;
    e.preventDefault(); e.stopImmediatePropagation();
    if (A().rol !== 'dueno') { avisar('La impresora fiscal la configura el dueño'); return; }
    openModal(configHtml());
  }, true);
  document.addEventListener('click', async e => {
    const b = e.target.closest('[data-act="mq-cfg"]'); if (!b) return;
    e.preventDefault(); e.stopImmediatePropagation();
    const val = id => (document.getElementById(id) || {}).value || '';
    const cambio = {medio_factura: 'maquina', maquina_marca: val('mq-marca').trim() || null, maquina_modelo: val('mq-modelo').trim() || null,
      maquina_registro: val('mq-reg').toUpperCase().replace(/[\s-]/g, '') || null, maquina_distribuidor: val('mq-dist').trim() || null,
      maquina_agente: val('mq-ag').trim().toLowerCase() || 'http://127.0.0.1:7123'};
    if (!cambio.maquina_registro) { avisar('Escribe el número de registro de la impresora'); return; }
    if (cambio.maquina_registro && !/^[A-Z0-9]{6,15}$/.test(cambio.maquina_registro)) { avisar('El número de registro lleva solo letras y números (6 a 15)'); return; }
    if (!/^(https?:\/\/(127\.0\.0\.1|localhost)(:\d{2,5})?\/?|simulada)$/.test(cambio.maquina_agente)) { avisar('El agente va en esta misma computadora: http://127.0.0.1:7123, o «simulada»'); return; }
    b.disabled = true;
    const {data, error} = await db.from('empresas').update(cambio).eq('id', EMP()).select().single();
    b.disabled = false;
    if (error) { avisar(C.msg(error)); return; }
    Object.assign(C.empresa || (C.empresa = {}), data);
    closeModal(); await alEntrar();
    avisar('Impresora fiscal guardada: la farmacia ya puede facturar');
    render();
  }, true);

  /* ---------------- Al entrar ---------------- */
  let reloj = null;
  async function alEntrar() {
    if (A().tipo !== 'farmacia') return;
    S.medio = 'maquina';   // la farmacia no tiene otro medio
    if (!activa()) { clearInterval(reloj); reloj = null; Object.assign(MAQ, {lista: false, estado: 'Sin configurar', corto: 'Impresora', modelo: 'Sin configurar', registro: '—', conexion: '—', memoria: null, ultFac: 0, ultZ: false}); return; }
    ponerDatos(); marcar(true);
    await Promise.all([refrescar().catch(x => console.error('Cuadre máquina: datos', x)), revisarEstado()]);
    if (!reloj) reloj = setInterval(revisarEstado, 60000);
    setTimeout(subirZPendiente, 3000);
  }
  C.alEntrar(alEntrar, 2);

  C.maquina = {imprimir, ventaSinInternet, refrescar, simular, activa,
    alCambiar: () => { refrescar().catch(() => {}); }};
})();
