/* =====================================================================
   Cuadre · Pantallas comunes con datos reales (los tres sistemas)
     * Usuarios: el equipo de este negocio, nuevo usuario, dar acceso,
       cambiar rol, caja o nombre, desactivar y cambiar la clave.
     * Configuración: los datos fiscales se guardan en la base.
     * Tasa BCV: se lee de la base; si falta la de hoy, la carga el dueño
       al entrar (o la escribe a mano).
   Va al final de cada HTML: usa S, V, FX, NAV, render, openModal… de la página.
   ===================================================================== */
(() => {
  const C = window.Cuadre;
  if (!C || !C.listo || C.comunListo) return;   // una sola vez, aunque el archivo se cargue dos veces
  C.comunListo = true;
  const db = C.db, esc = C.esc;
  const RTXT = {dueno: 'Dueño', gerente: 'Gerente', regente: 'Farmacéutico regente', cajero: 'Cajero', almacen: 'Almacén',
                atencion: 'Atención', bioanalista: 'Bioanalista', toma_muestras: 'Toma de muestras', coach: 'Coach', socio: 'Socio'};
  const DEL_SISTEMA = {farmacia: ['gerente', 'regente', 'cajero', 'almacen'], laboratorio: ['gerente', 'atencion', 'bioanalista', 'toma_muestras'], crossfit: ['gerente', 'coach']};
  const CAJAS = {farmacia: ['Caja 1', 'Caja 2', 'Almacén', 'Todas las cajas']};
  const hoyVE = () => new Intl.DateTimeFormat('en-CA', {timeZone: 'America/Caracas'}).format(new Date());
  const A = () => C.acceso || {};
  const soyDueno = () => A().rol === 'dueno';
  const puedoEquipo = () => ['dueno', 'gerente'].includes(A().rol);
  const avisar = t => (typeof toast === 'function' ? toast(t) : alert(t));
  const repintar = () => { if (typeof render === 'function') render(); };
  const icono = (n) => (typeof ic === 'function' ? ic(n) : '');
  const iniciales = n => String(n || '?').split(/\s+/).filter(w => /^[A-ZÁÉÍÓÚÑ]/i.test(w)).slice(0, 2).map(w => w[0].toUpperCase()).join('') || '?';
  const fechaHora = f => f ? new Date(f).toLocaleString('es-VE', {day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit'}) : 'Nunca ha entrado';

  /* ---------------- Fase 2: guardada, fuera de la vista ----------------
     Las pantallas de la fase 2 (Azul Puntos, tienda web, sucursales; portal, equipos, convenios,
     calidad y grupo del laboratorio) siguen en los archivos. Para volver a mostrarlas: FASE2 = true. */
  const FASE2 = false;
  C.alEntrar(async () => {
    if (FASE2 || typeof NAV !== 'object' || typeof V !== 'object') return;
    const i = NAV.findIndex(g => g.f2); if (i < 0) return;
    const vistas = NAV[i].items.map(it => it[1]); NAV.splice(i, 1);
    vistas.forEach(v => { V[v] = () => '<p class="lead">Esta pantalla es de la fase 2 y todavía no está activa.</p>'; });
    if (typeof F2 === 'object') F2.length = 0;
    if (Cuadre.destino && vistas.includes(Cuadre.destino)) Cuadre.destino = '';
  });
  /* Las páginas de la propuesta de venta («Alcance de la propuesta», «Alcance y regalo») no van al cliente */
  C.alEntrar(async () => {
    if (typeof NAV !== 'object' || typeof V !== 'object') return;
    for (let i = NAV.length - 1; i >= 0; i--) { NAV[i].items = NAV[i].items.filter(it => it[1] !== 'scope'); if (!NAV[i].items.length) NAV.splice(i, 1); }
    V.scope = () => '<p class="lead">Esta página no está disponible.</p>';
    if (Cuadre.destino === 'scope') Cuadre.destino = '';
  });
  if (!FASE2) document.head.insertAdjacentHTML('beforeend', '<style>.phase.f1,.phase.f2{display:none}</style>');

  /* La fecha de hoy de verdad (las maquetas traían una fija) */
  try { if (typeof TODAY === 'object' && TODAY.setTime) { const [y, m, d] = hoyVE().split('-').map(Number); TODAY.setTime(new Date(y, m - 1, d).getTime()); } } catch (_) {}

  /* ---------------- Sin conexión: el estado real del equipo ---------------- */
  const ponerRed = () => { if (typeof S === 'object' && 'online' in S) { S.online = navigator.onLine; if (S.view && S.view !== 'login') repintar(); } };
  window.addEventListener('online', ponerRed); window.addEventListener('offline', ponerRed);
  if (typeof S === 'object' && 'online' in S) S.online = navigator.onLine;
  // El botón de la maqueta que simulaba el corte ya no hace falta: el sistema lo detecta solo
  document.addEventListener('click', e => { const b = e.target.closest('[data-act="net"]'); if (!b || !C.acceso) return;
    e.stopImmediatePropagation(); avisar(navigator.onLine ? 'Hay internet: todo se guarda en la base al momento' : 'Sin internet: las ventas se guardan en este equipo y suben solas al volver'); }, true);
  // Copia local de lo necesario para abrir sin internet
  C.guardarLocal = (k, v) => { try { localStorage.setItem('cuadre.' + A().tipo + '.' + k, JSON.stringify(v)); } catch (_) {} };
  C.leerLocal = k => { try { return C.neutro(JSON.parse(localStorage.getItem('cuadre.' + A().tipo + '.' + k) || 'null')); } catch (_) { return null; } };   // también lo guardado en el equipo pasa por el filtro

  /* ---------------- Tasa BCV ---------------- */
  function ponerTasa(v, fecha) {
    if (!(v > 0)) return;
    if (typeof S === 'object' && 'rate' in S) S.rate = v;
    try { if (typeof RATE !== 'undefined') RATE = v; } catch (_) {}
    if (typeof bcvSet === 'function') { try { bcvSet(v, fecha); } catch (_) {} }
  }
  async function guardarTasa(v, fuente) {
    const {error} = await db.from('tasas_bcv').upsert({fecha: hoyVE(), tasa: v, fuente}, {onConflict: 'fecha'});
    if (error) throw error;
    ponerTasa(v, new Date().toISOString());
  }
  C.alEntrar(async () => {
    const {data, error} = await db.from('tasas_bcv').select('fecha,tasa').order('fecha', {ascending: false}).limit(1);
    const t = error ? C.leerLocal('tasa') : data && data[0];
    if (t) { ponerTasa(+t.tasa, t.fecha); if (!error) C.guardarLocal('tasa', t); }
    if (error) return;
    if ((!t || t.fecha < hoyVE()) && soyDueno()) {
      // En segundo plano: la entrada no espera a la fuente de la tasa
      (async () => {
        try {
          const j = await (await fetch('https://ve.dolarapi.com/v1/dolares/oficial', {cache: 'no-store'})).json();
          const v = +(j.promedio || j.venta);
          if (v > 0) { await guardarTasa(v, 'BCV vía dolarapi.com'); repintar(); }
        } catch (_) { /* sin internet o la fuente falló: el dueño la escribe en «Tasa BCV» */ }
      })();
    }
  });
  /* Farmacia: el formulario «Tasa BCV» guarda en la base */
  document.addEventListener('submit', async e => {
    if (e.target.id !== 'tasaForm') return;
    e.preventDefault(); e.stopImmediatePropagation();
    const v = typeof parseVE === 'function' ? parseVE(document.getElementById('t-val').value) : parseFloat(String(document.getElementById('t-val').value).replace(/\./g, '').replace(',', '.'));
    if (!v || v < 1) { avisar('Escribe la tasa en bolívares por dólar'); return; }
    try {
      await guardarTasa(v, 'Dueño');
      const m = document.getElementById('t-modo'); if (m && typeof CFG === 'object') CFG.tasaModo = m.value;
      closeModal(); repintar(); avisar('Tasa guardada: los precios en bolívares ya usan la nueva');
    } catch (x) { avisar(C.msg(x)); }
  }, true);

  /* ---------------- Datos fiscales ---------------- */
  const CAMPOS = {razon: 'razon_social', rif: 'rif', dom: 'domicilio', tel: 'telefono', impNom: 'imprenta_nombre', impRif: 'imprenta_rif',
                  serie: 'imprenta_serie', prov: 'providencia', talNum: 'talonario_num', talSerie: 'talonario_serie', talDesde: 'talonario_desde',
                  talHasta: 'talonario_hasta', contador: 'contador'};
  C.empresa = null;
  C.alEntrar(async a => {
    let {data, error} = await db.from('empresas').select('*').eq('id', a.empresa_id).single();
    if (error || !data) data = C.leerLocal('empresa'); else C.guardarLocal('empresa', data);
    if (!data) return;
    C.empresa = data;
    if (typeof FX === 'object' && FX.F) {
      Object.entries(CAMPOS).forEach(([k, col]) => { if (data[col] != null) FX.F[k] = data[col]; });
      FX.F.talDesde = data.talonario_desde; FX.F.talHasta = data.talonario_hasta;   // sin talonario cargado no se vende sin internet
      FX.F.rifMuestra = !data.datos_confirmados;
    }
  });
  const rifOk = r => /^[JGVEP]-\d{8}-\d$/.test(r);
  const normRif = r => String(r || '').toUpperCase().replace(/[.\s]/g, '').replace(/^([JGVEP])-?(\d{8})-?(\d)$/, '$1-$2-$3');
  document.addEventListener('submit', async e => {
    if (e.target.id !== 'fx-dform') return;
    e.preventDefault(); e.stopImmediatePropagation();
    const v = {}; e.target.querySelectorAll('[data-fxf]').forEach(i => { v[i.dataset.fxf] = i.value.trim(); });
    v.rif = normRif(v.rif); if (v.impRif) v.impRif = normRif(v.impRif);
    if (!v.razon || !v.dom) { avisar('Falta la razón social o el domicilio fiscal'); return; }
    if (!rifOk(v.rif)) { avisar('El RIF debe quedar así: J-12345678-9'); return; }
    if (v.impRif && !rifOk(v.impRif)) { avisar('El RIF de la imprenta debe quedar así: J-12345678-9'); return; }
    if ((v.talDesde || v.talHasta) && !(+v.talDesde >= 1 && +v.talHasta >= +v.talDesde)) { avisar('Revisa el talonario: el último número debe ser mayor que el primero'); return; }
    const fila = {datos_confirmados: document.getElementById('fx-f-conf').checked};
    Object.entries(CAMPOS).forEach(([k, col]) => { if (k in v) fila[col] = v[k] === '' && !['razon', 'rif', 'dom', 'serie'].includes(k) ? null : v[k]; });
    const b = e.target.querySelector('[type=submit]'); if (b) b.disabled = true;
    const {data, error} = await db.from('empresas').update(fila).eq('id', A().empresa_id).select().single();
    if (b) b.disabled = false;
    if (error) { avisar(/duplicate|unique/i.test(error.message) ? 'Ese RIF ya lo tiene otro negocio del grupo' : C.msg(error)); return; }
    if (!data) { avisar('Solo el dueño cambia los datos fiscales'); return; }
    C.empresa = data;
    await guardarFiscalMes(e.target);
    Object.entries(CAMPOS).forEach(([k, col]) => { if (data[col] != null) FX.F[k] = data[col]; });
    FX.F.talDesde = data.talonario_desde; FX.F.talHasta = data.talonario_hasta;
    FX.F.rifMuestra = !data.datos_confirmados;
    repintar();
    avisar(data.datos_confirmados ? 'Datos fiscales guardados. Este negocio ya puede facturar' : 'Datos guardados. Marca «confirmados» para poder facturar');
  }, true);

  const p8 = n => String(n).padStart(8, '0');
  const hm = f => new Date(f).toLocaleTimeString('es-VE', {hour: '2-digit', minute: '2-digit', hour12: false, timeZone: 'America/Caracas'});
  async function todo(armar) {
    const out = [];
    for (let i = 0; ; i += 1000) {
      const {data, error} = await armar().range(i, i + 999);
      if (error) throw error;
      out.push(...data);
      if (data.length < 1000) return out;
    }
  }
  C.todo = todo;

  /* ---------------- Facturas y notas del mes (motor fiscal común) ---------------- */
  let docId = 900000;
  const mapaDocs = new Map(); // uuid → id local del motor fiscal
  function aDocFX(d, nombres) {
    const id = ++docId; mapaDocs.set(d.id, id);
    const x = {id, tipo: d.tipo, fecha: new Intl.DateTimeFormat('en-CA', {timeZone: 'America/Caracas'}).format(new Date(d.fecha)), hora: hm(d.fecha),
      cli: {n: d.cliente_nombre, id: d.cliente_rif === 'V-00000000' ? '' : d.cliente_rif, tel: d.cliente_tel || ''},
      lines: (d.documento_lineas || []).sort((a, b) => a.renglon - b.renglon).map(l => ({d: l.descripcion, q: +l.cantidad, pu: +l.precio_unit, a: l.alicuota, pid: l.ref && l.ref.producto_id})),
      tasa: +d.tasa, div: 0, pagos: (d.documento_pagos || []).map(p => ({k: p.metodo, bs: +p.monto_bs})), origen: d.ref_tipo === 'venta' ? {sale: true} : null,
      afecta: d.afecta_id ? mapaDocs.get(d.afecta_id) || null : null, motivo: d.motivo || '', igtf: +d.igtf, u: nombres[d.creado_por] || '',
      cont: d.origen === 'contingencia', num: d.origen === 'contingencia' ? 'C-' + p8(d.numero) : p8(d.numero),
      ctrl: d.numero_control || 'Pendiente de imprenta', dbId: d.id};
    x.t = FX.tot(x); return x;
  }
  async function cargarDocumentos() {
    const desde = hoyVE().slice(0, 7) + '-01T00:00:00-04:00';
    const [docs, {data: per}, {data: ult}] = await Promise.all([
      todo(() => db.from('documentos').select('*, documento_lineas(*), documento_pagos(*)').eq('empresa_id', A().empresa_id).gte('fecha', desde).order('fecha')),
      db.from('perfiles').select('user_id,nombre'),
      db.from('documentos').select('tipo,numero').eq('empresa_id', A().empresa_id).eq('origen', 'sistema').order('numero', {ascending: false}).limit(50)]);
    const nombres = {}; (per || []).forEach(p => { nombres[p.user_id] = p.nombre; });
    FX.docs.length = 0; FX.hist.length = 0; mapaDocs.clear();
    docs.filter(d => d.tipo === 'FAC').concat(docs.filter(d => d.tipo !== 'FAC')).forEach(d => FX.docs.push(aDocFX(d, nombres)));
    // El próximo número que muestra la caja (la base asigna el definitivo)
    ['FAC', 'NC', 'ND'].forEach(t => { const u = (ult || []).find(x => x.tipo === t); FX.n[t] = u ? +u.numero + 1 : 1; });
  }
  C.cargarDocumentos = cargarDocumentos;
  C.docLocal = uuid => mapaDocs.get(uuid);

  /* Panel «Grupo Azullab · solo gerencia»: las ventas del mes de los otros negocios, de la base */
  const NEG = {farmacia: 'Farmacia', laboratorio: 'Laboratorio', crossfit: 'CrossFit'};
  let grupo = [];
  async function cargarGrupo() {
    // Se arma aparte y se cambia de una vez: si dos cargas se cruzan, no se suman filas repetidas
    const nuevo = [];
    if (A().rol !== 'dueno') { grupo = nuevo; return; }
    const {data: emps} = await db.from('empresas').select('id,tipo,razon_social,rif');
    const otras = (emps || []).filter(e => e.id !== A().empresa_id);
    const desde = hoyVE().slice(0, 7) + '-01T00:00:00-04:00';
    for (const e of otras) {
      const ds = await todo(() => db.from('documentos').select('tipo,total,iva_general,iva_reducida,igtf,estado').eq('empresa_id', e.id).gte('fecha', desde));
      const s = d => d.tipo === 'NC' ? -1 : 1, ok = ds.filter(d => d.estado !== 'rechazado');
      if (nuevo.some(g => g.tipo === e.tipo)) continue;
      nuevo.push({tipo: e.tipo, neg: NEG[e.tipo], razon: e.razon_social, rif: e.rif,
        v: Math.round(ok.reduce((t, d) => t + s(d) * (+d.total - +d.igtf), 0) * 100) / 100,
        iva: Math.round(ok.reduce((t, d) => t + s(d) * (+d.iva_general + +d.iva_reducida), 0) * 100) / 100});
    }
    grupo = nuevo;
  }
  if (typeof FX_SYS === 'object' && FX_SYS.grupo) {
    const grupoOriginal = FX_SYS.grupo;
    FX_SYS.grupo = M => {
      const propio = grupoOriginal(M).find(g => g.propio);
      // Un renglón por negocio: el propio y los demás, sin repetir
      return [propio, ...grupo.filter(g => g.tipo !== A().tipo)].filter(Boolean).sort((a, b) => Object.keys(NEG).indexOf(a.tipo || A().tipo) - Object.keys(NEG).indexOf(b.tipo || A().tipo));
    };
  }
  C.alEntrar(async () => { try { await cargarGrupo(); } catch (x) { console.error('Cuadre: grupo', x); } });

  /* Datos fiscales de muestra del motor que afectan cálculos: fuera.
     El excedente del mes anterior y la última declaración los pone el contador (colección privado_fiscal). */
  if (typeof FX_SYS === 'object') {
    FX_SYS.excedente = 0; FX_SYS.declPrev = '';
  }
  // Las facturas y el historial que el motor arma al arrancar son de la maqueta: fuera desde el inicio,
  // así no se ven aunque la base tarde o falle (las reales llegan con cargarDocumentos)
  if (typeof FX === 'object' && FX.docs) { FX.docs.length = 0; if (FX.hist) FX.hist.length = 0; if (FX.n) ['FAC', 'NC', 'ND'].forEach(t => { FX.n[t] = 1; }); }
  C.alEntrar(async a => {
    const compras = typeof FX_SYS === 'object' && a.tipo !== 'farmacia' ? cargarComprasServ().catch(x => console.error(x)) : null;
    const {data} = await db.from('colecciones').select('datos').eq('empresa_id', A().empresa_id).eq('nombre', 'privado_fiscal').maybeSingle();
    if (compras) { await compras; conectarComprasServ(); }
    if (data && data.datos && typeof FX_SYS === 'object') { FX_SYS.excedente = +data.datos.excedente || 0; FX_SYS.declPrev = data.datos.declPrev || ''; FX.F.excedente = String(FX_SYS.excedente).replace('.', ','); FX.F.declPrev = FX_SYS.declPrev; }
  });

  /* Notas de crédito y débito: las emite la base; la pantalla arma el documento con ese número */
  let notaPase = false, notaReal = null;
  if (typeof FX === 'object' && FX.emitir) {
    const fxEmitir = FX.emitir;
    FX.emitir = o => {
      const d = fxEmitir(o);
      if (notaReal && (o.tipo === 'NC' || o.tipo === 'ND')) {
        d.num = p8(notaReal.numero); d.ctrl = notaReal.numero_control || 'Pendiente de imprenta'; d.dbId = notaReal.id; d.cont = false;
        FX.n[o.tipo] = notaReal.numero + 1; notaReal = null;
      }
      return d;
    };
  }
  const bs = v => parseFloat(String(v || '').replace(/\./g, '').replace(',', '.')) || 0;
  document.addEventListener('click', async e => {
    const b = e.target.closest('[data-act="fx-ncgo"],[data-act="fx-ndgo"]'); if (!b) return;
    if (notaPase) { notaPase = false; return; }
    e.preventDefault(); e.stopImmediatePropagation();
    const otraVuelta = () => { notaPase = true; b.click(); };   // la pantalla muestra su propio aviso
    const fac = b.dataset.id ? FX.byId(b.dataset.id) : b.dataset.num ? FX.byNum(b.dataset.num) : null;
    if (!fac) return otraVuelta();
    if (!fac.dbId) { avisar('Esa factura no está en la base de datos'); return; }
    let tipo, lineas, motivo;
    if (b.dataset.act === 'fx-ncgo') {
      const ls = FX.ncLines();
      if (!ls.length || ls.some(l => !(l.q > 0) || l.q > l.max + 1e-9)) return otraVuelta();
      tipo = 'NC'; motivo = (document.getElementById('fx-mot') || {}).value || 'Nota de crédito';
      lineas = ls.map(l => ({descripcion: l.d, cantidad: l.q, precio_bs: l.pu, alicuota: l.a, ref: l.pid ? {producto_id: l.pid} : null}));
    } else {
      const m = bs((document.getElementById('fx-ndm') || {}).value); if (!(m > 0)) return otraVuelta();
      tipo = 'ND'; motivo = ((document.getElementById('fx-ndc') || {}).value || '').trim() || 'Ajuste';
      lineas = [{descripcion: motivo, cantidad: 1, precio_bs: m, alicuota: (document.getElementById('fx-nda') || {}).value || 'G'}];
    }
    const reintegrar = tipo === 'NC' && /devoluci|anulaci/i.test(motivo);
    b.disabled = true;
    const {data, error} = await db.rpc('emitir_nota', {p_factura: fac.dbId, p_tipo: tipo, p_lineas: lineas, p_motivo: motivo, p_reintegrar: reintegrar});
    b.disabled = false;
    if (error) { avisar(C.msg(error)); return; }
    notaReal = data; otraVuelta();
    if (C.farmacia && C.farmacia.alCambiarDocs) C.farmacia.alCambiarDocs();
    // Lo devuelto: la existencia que manda es la de la base
    if (reintegrar && C.farmacia) { await C.farmacia.recargar(lineas.filter(l => l.ref).map(l => l.ref.producto_id)); if (C.recargarControlados) await C.recargarControlados(); repintar(); }
  }, true);
  C.alEntrar(async () => { if (typeof FX === 'object' && FX.docs) await cargarDocumentos(); });

  /* ---------------- Facturas de compra (laboratorio y CrossFit): libro de compras y retenciones ---------------- */
  let comprasServ = [];
  const dmyC = iso => iso.slice(8, 10) + '/' + iso.slice(5, 7) + '/' + iso.slice(0, 4);
  async function cargarComprasServ() {
    comprasServ = [];
    if (!['dueno', 'gerente'].includes(A().rol)) return;
    const desde = hoyVE().slice(0, 7) + '-01';
    comprasServ = await todo(() => db.from('compras').select('*').eq('empresa_id', A().empresa_id).gte('fecha', desde).order('fecha'));
  }
  const delMesC = c => c.fecha.slice(0, 7) === hoyVE().slice(0, 7);
  function conectarComprasServ() {
    FX_SYS.compras = () => comprasServ.filter(delMesC).map(c => { const d = c.datos || {};
      return {f: c.fecha, tipo: c.tipo, num: c.numero, ctrl: c.control || '', afecta: '', rif: c.rif || '', prov: c.proveedor,
        ex: d.exento_bs != null ? +d.exento_bs : Math.round(c.exento_usd * c.tasa * 100) / 100, bg: d.gravable_bs != null ? +d.gravable_bs : Math.round(c.gravable_usd * c.tasa * 100) / 100}; });
    FX_SYS.islr = () => comprasServ.filter(c => delMesC(c) && c.datos && c.datos.retencion && c.datos.retencion.k).map(c => { const d = c.datos;
      return {f: c.fecha, ben: c.proveedor, rif: c.rif || '', k: d.retencion.k, pn: !!d.retencion.pn, bsA: (+d.exento_bs || 0) + (+d.gravable_bs || 0), comp: d.retencion.comp || 'Por entregar'}; });
    const vLibros = V.libros;
    V.libros = () => (['dueno', 'gerente'].includes(A().rol) ? `<div class="row" style="margin-bottom:12px"><p class="lead" style="margin:0">Las facturas de tus proveedores (reactivos, insumos, servicios, alquiler) entran al Libro de Compras; si les retuviste ISLR, el comprobante sale solo.</p><span class="spacer"></span><button class="btn primary" data-act="cx-compra">${icono('plus')}Registrar factura de compra</button></div>` : '') + vLibros();
  }
  const compraModal = () => hoja('Factura de compra', `<form class="bd" id="cx-compra-f" style="display:grid;gap:10px">
      <div class="grid g2" style="gap:10px"><div class="field"><label for="cx-p">Proveedor</label><input id="cx-p" class="input" required list="cx-provs"><datalist id="cx-provs">${[...new Set(comprasServ.map(c => c.proveedor))].map(p => `<option>${esc(p)}</option>`).join('')}</datalist></div>
        <div class="field"><label for="cx-r">RIF del proveedor</label><input id="cx-r" class="input num" placeholder="J-00000000-0"></div></div>
      <div class="grid g2" style="gap:10px"><div class="field"><label for="cx-n">N° de factura</label><input id="cx-n" class="input num" required></div>
        <div class="field"><label for="cx-c">N° de control</label><input id="cx-c" class="input num" placeholder="00-000000"></div></div>
      <div class="grid g2" style="gap:10px"><div class="field"><label for="cx-f">Fecha</label><input id="cx-f" class="input" type="date" value="${hoyVE()}"></div><div></div></div>
      <div class="grid g2" style="gap:10px"><div class="field"><label for="cx-e">Monto exento (Bs)</label><input id="cx-e" class="input num" inputmode="decimal" placeholder="0,00"></div>
        <div class="field"><label for="cx-g">Base gravable (Bs, sin IVA)</label><input id="cx-g" class="input num" inputmode="decimal" placeholder="0,00"></div></div>
      <div class="grid g2" style="gap:10px"><div class="field"><label for="cx-k">Retención de ISLR</label><select id="cx-k" class="input"><option value="">No se retuvo</option>${Object.entries(FX.ISLR || {}).map(([k, v]) => `<option value="${k}">${esc(v[0])}</option>`).join('')}</select></div>
        <label class="row" style="gap:8px;align-self:end"><input type="checkbox" id="cx-pn"><span>El proveedor es persona natural</span></label></div>
      ${pie('Registrar factura')}</form>`);
  document.addEventListener('click', e => { if (!e.target.closest('[data-act="cx-compra"]')) return; e.stopImmediatePropagation(); openModal(compraModal()); }, true);
  document.addEventListener('submit', async e => {
    if (e.target.id !== 'cx-compra-f') return;
    e.preventDefault(); e.stopImmediatePropagation();
    const g = id => (document.getElementById(id).value || '').trim(), nb = v => parseFloat(String(v || '').replace(/\./g, '').replace(',', '.')) || 0;
    const k = g('cx-k');
    const {error} = await db.rpc('registrar_compra', {p_empresa: A().empresa_id, p_factura: {proveedor: g('cx-p'), rif: g('cx-r'), numero: g('cx-n'), control: g('cx-c'), fecha: g('cx-f'),
      exento_bs: nb(g('cx-e')), gravable_bs: nb(g('cx-g')), retencion: k ? {k, pn: document.getElementById('cx-pn').checked} : null}});
    if (error) { errModal(/duplicate/i.test(error.message) ? 'Esa factura de ese proveedor ya está registrada' : C.msg(error)); return; }
    await cargarComprasServ(); closeModal(); repintar(); avisar('Factura registrada en el Libro de Compras');
  }, true);

  /* Excedente del mes anterior y última declaración: los guarda Datos fiscales */
  async function guardarFiscalMes(form) {
    const ex = form.querySelector('[data-fxf="excedente"]'), dp = form.querySelector('[data-fxf="declPrev"]'); if (!ex) return;
    const datos = {excedente: parseFloat(String(ex.value || '0').replace(/\./g, '').replace(',', '.')) || 0, declPrev: (dp.value || '').trim()};
    const {error} = await db.from('colecciones').upsert({empresa_id: A().empresa_id, nombre: 'privado_fiscal', datos, actualizado: new Date().toISOString()}, {onConflict: 'empresa_id,nombre'});
    if (!error) { FX_SYS.excedente = datos.excedente; FX_SYS.declPrev = datos.declPrev; FX.F.excedente = ex.value; FX.F.declPrev = datos.declPrev; }
  }

  /* ---------------- Usuarios ---------------- */
  const EQ = {lista: null, cargando: false, error: ''};
  async function cargarEquipo() {
    EQ.cargando = true; EQ.error = '';
    const {data, error} = await db.rpc('equipo', {p_empresa: A().empresa_id});
    EQ.cargando = false; EQ.lista = error ? [] : data.filter(u => u.rol !== 'socio');   // los socios se manejan desde su ficha EQ.error = error ? C.msg(error) : '';
    if (S.view === 'users') repintar();
  }
  const rolesOfrecidos = () => (soyDueno() ? ['dueno'] : []).concat(DEL_SISTEMA[A().tipo] || []);
  const opciones = (vals, sel, txt = x => x) => vals.map(x => `<option value="${esc(x)}" ${x === sel ? 'selected' : ''}>${esc(txt(x))}</option>`).join('');
  const campoCaja = (val) => CAJAS[A().tipo]
    ? `<div class="field"><label for="cq-caja">Caja</label><select id="cq-caja" class="input">${opciones(CAJAS[A().tipo], val || CAJAS[A().tipo][0])}</select></div>` : '';
  const hoja = (titulo, cuerpo) => `<div class="sheet" role="dialog" aria-modal="true" aria-labelledby="cq-t" style="max-width:520px"><div class="hd"><h2 id="cq-t">${titulo}</h2><button class="x" data-act="close" aria-label="Cerrar">${icono('x')}</button></div>${cuerpo}</div>`;
  const pie = (txt) => `<p id="cq-err" class="small" role="alert" style="color:var(--bad,#b3261e);margin:0" hidden></p><button class="btn primary big" type="submit">${icono('check')}${txt}</button>`;

  function vistaUsuarios() {
    if (!puedoEquipo()) return '<p class="lead">Solo el dueño o el gerente manejan los usuarios.</p>';
    if (EQ.lista === null && !EQ.cargando) cargarEquipo();
    const L = EQ.lista || [];
    const filas = EQ.lista === null ? '<div class="it"><div class="t"><span class="muted">Cargando el equipo…</span></div></div>'
      : L.map((u, i) => `<div class="it"><span class="av">${esc(iniciales(u.nombre))}</span><div class="t"><b>${esc(u.nombre)}</b>
          <span class="small muted">${esc(RTXT[u.rol] || u.rol)}${u.caja ? ' · ' + esc(u.caja) : ''} · ${esc(u.correo)} · ${esc(fechaHora(u.ultima_entrada))}${u.activo ? '' : ' · <span style="color:var(--bad)">Sin acceso</span>'}</span></div>
          ${u.user_id === EQ.yo ? '<span class="pill ghost">Tú</span>' : `<button class="btn sm" data-act="cq-editar" data-i="${i}">${icono('edit')}Editar</button>`}</div>`).join('');
    const qv = Object.entries(ROLES).map(([r, x]) => `<div class="stat" style="align-items:start"><b>${esc(r)}</b><span class="small muted" style="text-align:right;max-width:70%">${esc(x.desc || '')}</span></div>`).join('');
    return `<div class="row"><p class="lead">Cada persona entra con su correo y su clave, y el sistema le abre solo lo de su rol. Todo lo que hace queda registrado con su nombre y la hora.</p><span class="spacer"></span>
      <button class="btn" data-act="cq-acceso">${icono('key')}Dar acceso</button><button class="btn primary" data-act="cq-nuevo">${icono('plus')}Nuevo usuario</button></div>
      ${EQ.error ? `<p class="small" style="color:var(--bad)">${esc(EQ.error)}</p>` : ''}
      <div class="grid g2" style="align-items:start">
      <section class="panel"><div class="hd"><h2>Equipo de ${esc(A().empresa || '')}</h2><span class="muted small">${L.filter(u => u.activo).length} con acceso</span></div><div class="bd flush list">${filas}</div></section>
      <section class="panel"><div class="hd"><h2>Qué ve cada rol</h2></div><div class="bd">${qv}
        <p class="small muted" style="margin:10px 0 0">«Dar acceso» sirve para alguien que ya tiene usuario en otro negocio del grupo: entra con el mismo correo y aquí tiene su propio rol. Para entrar con PIN en la caja: menú «Este equipo».</p></div></section></div>`;
  }

  /* ---------------- Este equipo: registro, PIN e instalación ---------------- */
  const DISP = () => window.CuadreEquipo;
  const instalada = () => window.matchMedia && matchMedia('(display-mode: standalone)').matches;
  function panelEquipo() {
    const D = DISP(), t = A().tipo; if (!D) return '';
    const inst = instalada() ? '<span class="pill ok">App instalada en este equipo</span>'
      : C.instalar ? `<button class="btn" data-act="eq-instalar">${icono('download')}Instalar la app en este equipo</button>`
      : `<span class="small muted">Para instalarla: en Chrome o Edge, el ícono de instalar al final de la barra de direcciones, o menú ⋮ → «Instalar ${esc(A().empresa || 'Azullab')}».</span>`;
    if (!D.disponible()) return `<section class="panel"><div class="hd"><h2>Este equipo</h2></div><div class="bd"><p class="small muted" style="margin:0">La entrada con PIN necesita el sistema publicado con https (por ejemplo, GitHub Pages). Abierto como archivo del equipo no se puede.</p></div></section>`;
    const eq = D.equipo(t);
    if (!eq) return `<section class="panel"><div class="hd"><h2>Este equipo</h2><span class="pill ghost">Sin registrar</span></div><form class="bd" id="eq-reg-f" style="display:grid;gap:10px">
      <p class="small muted" style="margin:0">Registra las computadoras de uso fijo (la caja, la recepción). En un equipo registrado cada persona entra con su PIN, aunque no haya internet. No registres tu celular ni una computadora prestada.</p>
      <div class="field"><label for="eq-nom">Nombre del equipo</label><input id="eq-nom" class="input" placeholder="Caja 1" maxlength="40" required></div>
      <button class="btn primary" type="submit">${icono('check')}Registrar este equipo</button><div>${inst}</div></form></section>`;
    const yo = (C.acceso || {}).uid, ps = D.personas(t), f = x => new Date(x).toLocaleString('es-VE', {day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit'});
    return `<section class="panel"><div class="hd"><h2>Este equipo · ${esc(eq.nombre)}</h2><span class="pill ok">Registrado</span></div>
      <div class="bd flush list">${ps.length ? ps.map(p => `<div class="it"><span class="av">${esc(iniciales(p.nombre))}</span><div class="t"><b>${esc(p.nombre)}</b>
        <span class="small muted">${esc(p.rol)} · última conexión ${esc(f(p.ultima))}${p.bloqueado ? ' · <span style="color:var(--bad)">Bloqueado</span>' : p.vencido ? ' · <span style="color:var(--bad)">Vencido</span>' : ''}</span></div>
        <button class="btn sm" data-act="eq-quitar-pin" data-uid="${esc(p.uid)}">Quitar PIN</button></div>`).join('')
        : '<div class="it"><div class="t"><span class="muted">Nadie tiene PIN todavía. Cada persona lo crea la primera vez que entra aquí con su correo y su clave.</span></div></div>'}</div>
      <div class="bd" style="display:grid;gap:10px">
        <div class="row" style="gap:8px;flex-wrap:wrap">${yo && !D.tienePin(t, yo) ? `<button class="btn primary" data-act="eq-mi-pin">${icono('key')}Crear mi PIN</button>` : ''}
          <button class="btn" data-act="eq-quitar">Quitar el registro</button></div>
        <div>${inst}</div>
        <p class="small muted" style="margin:0">5 PIN errados bloquean a esa persona en este equipo y 7 días sin conexión vencen su PIN: en los dos casos vuelve a entrar con su correo y su clave. Si le quitas el acceso en «Usuarios», su PIN deja de servir apenas el equipo tenga internet.</p></div></section>`;
  }
  document.addEventListener('submit', async e => {
    if (!['eq-reg-f', 'eq-pin-f'].includes(e.target.id)) return;
    e.preventDefault(); e.stopImmediatePropagation();
    const D = DISP(), t = A().tipo;
    if (e.target.id === 'eq-reg-f') {
      if (!puedoEquipo()) { avisar('Solo el dueño o el gerente registran equipos'); return; }
      D.registrar(t, document.getElementById('eq-nom').value, A().nombre); repintar();
      avisar('Equipo registrado. Crea tu PIN aquí abajo; los demás lo crean la primera vez que entren en este equipo'); return;
    }
    const p1 = document.getElementById('eq-p1').value, p2 = document.getElementById('eq-p2').value;
    if (p1 !== p2) { errModal('Los dos PIN no son iguales'); return; }
    try { await C.crearMiPin(p1); closeModal(); repintar(); avisar('PIN guardado: la próxima vez entras aquí con tu PIN'); } catch (x) { errModal(C.msg(x)); }
  }, true);
  document.addEventListener('click', async e => {
    const b = e.target.closest('[data-act^="eq-"]'); if (!b) return;
    e.preventDefault(); e.stopImmediatePropagation();
    const D = DISP(), t = A().tipo, act = b.dataset.act;
    if (act === 'eq-instalar' && C.instalar) { const ev = C.instalar; ev.prompt(); try { await ev.userChoice; } catch (_) {} window.__cuadreInstalar = null; repintar(); }
    else if (act === 'eq-mi-pin') openModal(hoja('Crear mi PIN para este equipo', `<form class="bd" id="eq-pin-f" style="display:grid;gap:10px">
      <p class="small muted" style="margin:0">De 4 a 6 números. No uses repetidos (1111) ni seguidos (1234).</p>
      <div class="field"><label for="eq-p1">PIN</label><input id="eq-p1" class="input" type="password" inputmode="numeric" pattern="[0-9]*" maxlength="6" autocomplete="off" required></div>
      <div class="field"><label for="eq-p2">Repite el PIN</label><input id="eq-p2" class="input" type="password" inputmode="numeric" pattern="[0-9]*" maxlength="6" autocomplete="off" required></div>${pie('Guardar PIN')}</form>`));
    else if (act === 'eq-quitar-pin') { if (!puedoEquipo()) return; D.quitar(t, b.dataset.uid); repintar(); avisar('PIN quitado: esa persona vuelve a entrar con su correo y su clave'); }
    else if (act === 'eq-quitar') { if (!puedoEquipo() || !confirm('¿Quitar el registro de este equipo? Se borran todos los PIN guardados aquí.')) return; D.quitarEquipo(t); repintar(); avisar('Este equipo ya no está registrado'); }
  }, true);
  const modalNuevo = () => hoja('Nuevo usuario', `<form class="bd" id="cq-nuevo-f" style="display:grid;gap:10px">
      <div class="field"><label for="cq-nom">Nombre y apellido</label><input id="cq-nom" class="input" required></div>
      <div class="field"><label for="cq-correo">Correo</label><input id="cq-correo" class="input" type="email" autocomplete="off" required></div>
      <div class="field"><label for="cq-clave">Clave inicial (mínimo 8)</label><input id="cq-clave" class="input" type="text" minlength="8" autocomplete="off" required></div>
      <div class="grid g2" style="gap:10px"><div class="field"><label for="cq-rol">Rol</label><select id="cq-rol" class="input">${opciones(rolesOfrecidos(), DEL_SISTEMA[A().tipo][1], r => RTXT[r])}</select></div>${campoCaja()}</div>
      <p class="small muted" style="margin:0">Entrégale el correo y la clave. Puede cambiar la clave con «Olvidé mi clave».</p>${pie('Crear usuario')}</form>`);
  const modalAcceso = () => hoja('Dar acceso con un usuario que ya existe', `<form class="bd" id="cq-acceso-f" style="display:grid;gap:10px">
      <div class="field"><label for="cq-correo">Correo con el que ya entra</label><input id="cq-correo" class="input" type="email" required></div>
      <div class="grid g2" style="gap:10px"><div class="field"><label for="cq-rol">Rol en ${esc(A().empresa || 'este negocio')}</label><select id="cq-rol" class="input">${opciones(rolesOfrecidos(), DEL_SISTEMA[A().tipo][1], r => RTXT[r])}</select></div>${campoCaja()}</div>${pie('Dar acceso')}</form>`);
  const modalEditar = (i) => { const u = EQ.lista[i];
    return hoja(esc(u.nombre), `<form class="bd" id="cq-editar-f" data-i="${i}" style="display:grid;gap:10px">
      <div class="field"><label for="cq-nom">Nombre y apellido</label><input id="cq-nom" class="input" value="${esc(u.nombre)}" required></div>
      <div class="grid g2" style="gap:10px"><div class="field"><label for="cq-rol">Rol</label><select id="cq-rol" class="input">${opciones([...new Set(rolesOfrecidos().concat(u.rol))], u.rol, r => RTXT[r])}</select></div>${campoCaja(u.caja)}</div>
      <label class="row" style="gap:8px"><input type="checkbox" id="cq-activo" ${u.activo ? 'checked' : ''}><span>Tiene acceso a este negocio</span></label>
      <div class="field"><label for="cq-clave">Clave nueva (déjala vacía para no cambiarla)</label><input id="cq-clave" class="input" type="text" minlength="8" autocomplete="off"></div>
      <p class="small muted" style="margin:0">${esc(u.correo)}</p>${pie('Guardar')}</form>`); };

  C.llamarUsuarios = cuerpo => llamarUsuarios(cuerpo);
  async function llamarUsuarios(cuerpo) {
    const {data, error} = await db.functions.invoke('usuarios', {body: cuerpo});
    if (error) {
      let m = error.message;
      try { const j = await error.context.json(); if (j && j.error) m = j.error; } catch (_) {}
      if (/Failed to send|not found|404/i.test(m)) m = 'Falta subir la función «usuarios» a Supabase (Edge Functions). Mientras tanto, crea el usuario en Supabase → Authentication y usa «Dar acceso».';
      throw new Error(m);
    }
    return data;
  }
  const errModal = t => { const p = document.getElementById('cq-err'); if (p) { p.textContent = t; p.hidden = !t; } else avisar(t); };

  document.addEventListener('click', e => {
    const b = e.target.closest('[data-act^="cq-"]'); if (!b) return;
    e.stopImmediatePropagation();
    if (b.dataset.act === 'cq-nuevo') openModal(modalNuevo());
    if (b.dataset.act === 'cq-acceso') openModal(modalAcceso());
    if (b.dataset.act === 'cq-editar') openModal(modalEditar(+b.dataset.i));
  }, true);

  document.addEventListener('submit', async e => {
    const id = e.target.id; if (!/^cq-(nuevo|acceso|editar)-f$/.test(id)) return;
    e.preventDefault(); e.stopImmediatePropagation();
    const val = k => { const x = document.getElementById(k); return x ? (x.type === 'checkbox' ? x.checked : x.value.trim()) : null; };
    const b = e.target.querySelector('[type=submit]'); b.disabled = true; errModal('');
    try {
      if (id === 'cq-nuevo-f') {
        await llamarUsuarios({accion: 'crear', empresa_id: A().empresa_id, nombre: val('cq-nom'), correo: val('cq-correo'), clave: val('cq-clave'), rol: val('cq-rol'), caja: val('cq-caja')});
        avisar(`${val('cq-nom')} ya puede entrar con su correo`);
      } else if (id === 'cq-acceso-f') {
        const {error} = await db.rpc('dar_acceso', {p_empresa: A().empresa_id, p_correo: val('cq-correo'), p_rol: val('cq-rol'), p_caja: val('cq-caja')});
        if (error) throw error;
        avisar('Acceso dado: entra con el mismo correo y clave');
      } else {
        const u = EQ.lista[+e.target.dataset.i];
        if (val('cq-nom') !== u.nombre) {
          const {data, error} = await db.from('perfiles').update({nombre: val('cq-nom')}).eq('user_id', u.user_id).select();
          if (error) throw error; if (!data.length) throw new Error('Solo el dueño cambia los nombres');
        }
        const cambio = {rol: val('cq-rol'), activo: val('cq-activo')}; if (CAJAS[A().tipo]) cambio.caja = val('cq-caja');
        if (cambio.rol !== u.rol || cambio.activo !== u.activo || (cambio.caja !== undefined && cambio.caja !== u.caja)) {
          const {data, error} = await db.from('miembros').update(cambio).eq('user_id', u.user_id).eq('empresa_id', A().empresa_id).select();
          if (error) throw error; if (!data.length) throw new Error('Solo el dueño cambia roles y accesos');
        }
        if (val('cq-clave')) await llamarUsuarios({accion: 'clave', empresa_id: A().empresa_id, user_id: u.user_id, clave: val('cq-clave')});
        avisar('Cambios guardados');
      }
      closeModal(); await cargarEquipo();
    } catch (x) { errModal(C.msg(x)); b.disabled = false; }
  }, true);

  C.alEntrar(async () => {
    const {data} = await db.auth.getSession(); EQ.yo = data && data.session && data.session.user.id; EQ.lista = null;   // ya está en el equipo: sin ir al servidor
    if (typeof V !== 'object') return;
    V.users = vistaUsuarios;
    /* El sistema que no tenía la pantalla (CrossFit) la recibe en «Sistema» */
    if (typeof NAV === 'object' && !NAV.some(g => g.items.some(it => it[1] === 'users'))) {
      let g = NAV.find(x => x.g === 'Sistema'); if (!g) { g = {g: 'Sistema', items: []}; NAV.push(g); }
      g.items.unshift(['key', 'users', 'Usuarios']);
      if (typeof TITLES === 'object') TITLES.users = 'Usuarios';
      if (typeof CODE === 'object') CODE.users = 'US';
    }
    /* «Este equipo» (registro, PIN e instalación), justo después de Usuarios: solo dueño y gerente */
    V.equipo = () => puedoEquipo() ? `<p class="lead">Registra aquí las computadoras de uso fijo (la caja, la recepción) e instala la app. En un equipo registrado cada persona entra con su PIN, con o sin internet.</p>${panelEquipo()}`
      : '<p class="lead">Solo el dueño o el gerente registran equipos.</p>';
    if (typeof NAV === 'object' && !NAV.some(g => g.items.some(it => it[1] === 'equipo'))) {
      const g = NAV.find(x => x.items.some(it => it[1] === 'users'));
      if (g) g.items.splice(g.items.findIndex(it => it[1] === 'users') + 1, 0, ['key', 'equipo', 'Este equipo']);
      if (typeof TITLES === 'object') TITLES.equipo = 'Este equipo';
      if (typeof CODE === 'object') CODE.equipo = 'EQ';
    }
  });
})();
