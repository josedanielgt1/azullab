/* =====================================================================
   Cuadre · Acceso común de los sistemas del Grupo Azullab
   Se entra con correo y clave (Supabase Auth). El sistema busca en la
   base el rol de esa persona en este negocio y abre sus pantallas:
   nadie escoge su rol en la entrada.
   Necesita, antes de este archivo:
     <script src="js/vendor/supabase-2.118.0.js"></script>   (copia local: abre sin internet)
     <script src="js/config.js"></script>
   ===================================================================== */
/* Seguridad: publicado en internet, el navegador solo deja que la página hable con la base de datos,
   la fuente de la tasa BCV y las letras de Google. Aunque alguien colara código, no podría mandar
   los datos ni la sesión a ningún otro sitio. (Abierto como archivo del equipo no se aplica: allí
   algunos navegadores bloquearían el propio sistema.) */
if (location.protocol !== 'file:' && window.CUADRE_CONFIG && window.CUADRE_CONFIG.url) {
  const base = window.CUADRE_CONFIG.url.replace(/\/+$/, ''), ws = base.replace(/^http/, 'ws');
  const m = document.createElement('meta'); m.httpEquiv = 'Content-Security-Policy';
  m.content = ["default-src 'self'", "script-src 'self' 'unsafe-inline'", "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    "font-src 'self' data: https://fonts.gstatic.com", "img-src 'self' data: blob:", `connect-src 'self' ${base} ${ws} https://ve.dolarapi.com`,
    "frame-src 'none'", "object-src 'none'", "base-uri 'self'", "form-action 'self'"].join('; ');
  document.head.appendChild(m);
}

/* Publicado en internet (https), el sistema queda guardado en el equipo y abre sin conexión */
if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('sw.js').catch(() => {});
/* «Instalar Cuadre» en el equipo: el navegador avisa que se puede; el botón está en Usuarios → Este equipo */
window.addEventListener('beforeinstallprompt', e => { e.preventDefault(); window.__cuadreInstalar = e; });
window.addEventListener('appinstalled', () => { window.__cuadreInstalar = null; });

window.Cuadre = (() => {
  const C = window.CUADRE_CONFIG || {};
  const listo = !!(C.url && C.key && window.supabase);

  /* Seguridad: las pantallas arman HTML con los datos (nombres de clientes, productos, pacientes…).
     Para que nadie pueda esconder código en un nombre y robar la sesión de otro usuario, todo texto
     que llega de la base pasa por aquí: los caracteres que abren código (< > " `) se cambian por
     otros casi iguales a la vista que el navegador no interpreta. */
  const NEUTRO = {'<': '‹', '>': '›', '"': '”', '`': 'ʼ'};
  const neutro = v => typeof v === 'string' ? v.replace(/[<>"`]/g, c => NEUTRO[c])
    : Array.isArray(v) ? v.map(neutro)
    : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, neutro(x)])) : v;
  const fetchSeguro = async (entrada, opciones) => {
    const r = await fetch(entrada, opciones);
    const url = typeof entrada === 'string' ? entrada : (entrada && entrada.url) || '';
    if (!/\/(rest|functions)\/v1\//.test(url) || !/json/.test(r.headers.get('content-type') || '') || r.status === 204) return r;
    const texto = await r.clone().text(); if (!texto) return r;
    let datos; try { datos = JSON.parse(texto); } catch (_) { return r; }
    return new Response(JSON.stringify(neutro(datos)), {status: r.status, statusText: r.statusText, headers: r.headers});
  };
  const db = listo ? window.supabase.createClient(C.url, C.key, {auth: {persistSession: true, storageKey: 'cuadre.sesion'}, global: {fetch: fetchSeguro}}) : null;

  /* Rol de la base → nombre del rol en cada sistema (las llaves de ROLES en cada HTML) */
  const ROLES = {
    farmacia:    {dueno: 'Dueño', gerente: 'Dueño', regente: 'Farmacéutico', cajero: 'Cajero', almacen: 'Almacén'},
    laboratorio: {dueno: 'Dueño', gerente: 'Dueño', bioanalista: 'Bioanalista', atencion: 'Atención', toma_muestras: 'Toma de muestras'},
    crossfit:    {dueno: 'Dueño', gerente: 'Dueño', coach: 'Coach', socio: 'Socio'}
  };
  const ERR = {
    'Invalid login credentials': 'Correo o clave incorrectos',
    'Email not confirmed': 'Ese correo todavía no está confirmado',
    'Failed to fetch': 'No hay conexión con el servidor. Revisa el internet'
  };
  const msg = e => ERR[e && e.message] || (e && e.message) || 'No se pudo entrar';
  const cache = t => 'cuadre.acceso.' + t;
  /* Equipo registrado y PIN (js/cuadre-equipo.js) */
  const EQ = () => window.CuadreEquipo || null;
  const K_SESION = 'cuadre.sesion';
  const sesionGuardada = () => { try { const s = JSON.parse(localStorage.getItem(K_SESION) || 'null'); return s && s.user ? s : null; } catch (_) { return null; } };
  const usaPin = t => !!(EQ() && EQ().disponible() && EQ().equipo(t));
  const errorDeRed = x => !navigator.onLine || /fetch|network|retryable|load failed/i.test(String(x && ((x.name || '') + ' ' + (x.message || ''))));
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));

  async function acceso(tipo) {
    const {data, error} = await db.rpc('mi_acceso', {p_tipo: tipo});
    if (error) throw error;
    const a = data && data[0];
    if (!a) throw new Error('Tu usuario no tiene un rol en este negocio. Pídele al dueño que te lo asigne.');
    const rol = ROLES[tipo][a.rol];
    if (!rol) throw new Error('Tu rol no tiene pantallas en este sistema.');
    const s = sesionGuardada(), r = {...a, rolTxt: rol, uid: s ? s.user.id : ''};
    try { localStorage.setItem(cache(tipo), JSON.stringify(r)); } catch (_) {}
    return r;
  }

  const ganchos = [];
  const api = {
    listo, db, destino: '', acceso: null, ROLES, msg, esc, neutro,
    modoClave: false, quien: null, pidePin: null, pinErr: '',
    get instalar() { return window.__cuadreInstalar || null; },
    /* Lo que se carga de la base al entrar, antes de abrir la primera pantalla */
    /* Lo que se carga al entrar. Los de una misma fase van a la vez; la fase 1 (lo propio de cada
       negocio) espera a la 0 (lo común: empresa, tasa, facturas) */
    alEntrar(fn, fase = 0) { ganchos.push({fn, fase}); },

    /* El formulario de entrada (lo mismo en los tres sistemas) */
    formulario(subtitulo) {
      const aviso = !listo
        ? '<div class="aviso-off" role="status"><span><b>Falta conectar la base de datos.</b> Copia la URL y la clave pública de Supabase en <code>js/config.js</code>.</span></div>'
        : !navigator.onLine
          ? '<div class="aviso-off" role="status"><span><b>Sin internet.</b> Si ya entraste antes en este equipo, el sistema abre con la sesión guardada. La primera vez hace falta conexión.</span></div>'
          : '';
      const E = EQ(), tipo = api._tipo;
      if (api.pidePin && E) return `<form id="pinNuevo" style="display:grid;gap:12px">
        <div><h2 style="font-size:1.4rem;margin:0">Crea tu PIN para este equipo</h2>
        <p class="muted" style="margin-top:6px">Equipo: <b>${esc((E.equipo(tipo) || {}).nombre)}</b>. Desde ahora entras aquí solo con tu PIN, aunque no haya internet. Son de 4 a 6 números; no uses repetidos (1111) ni seguidos (1234).</p></div>
        <div class="field"><label for="pin1">PIN</label><input id="pin1" class="input" type="password" inputmode="numeric" pattern="[0-9]*" maxlength="6" autocomplete="off" required></div>
        <div class="field"><label for="pin2">Repite el PIN</label><input id="pin2" class="input" type="password" inputmode="numeric" pattern="[0-9]*" maxlength="6" autocomplete="off" required></div>
        <p id="login-err" class="small" role="alert" style="color:var(--bad,#b3261e);margin:0" hidden></p>
        <button class="btn primary big" type="submit">Guardar PIN y entrar</button>
        <button type="button" class="btn sm" data-act="cuadre-sin-pin" style="justify-self:start">Ahora no</button></form>`;
      if (api.restaurando) return `<div id="cuadre-abriendo" style="display:grid;gap:12px;justify-items:start" role="status">
        <h2 style="font-size:1.4rem;margin:0">Abriendo tu sesión…</h2>
        <p class="muted" style="margin:0">${esc(subtitulo)}. Un momento: estamos cargando tus datos.</p>
        <button type="button" class="btn sm" data-act="cuadre-otra">Entrar con otra cuenta</button></div>`;
      const nota = api.notaEntrada ? `<div class="aviso-off" role="status"><span>${esc(api.notaEntrada)}</span></div>` : '';
      const conPin = listo && usaPin(tipo) ? E.personas(tipo) : [];
      if (conPin.length && !api.modoClave) {
        const yo = conPin.find(p => p.uid === api.quien && !p.bloqueado && !p.vencido);
        return `${!navigator.onLine ? '<div class="aviso-off" role="status"><span><b>Sin internet.</b> Entra con tu PIN: lo que hagas queda en el equipo y sube solo al volver la conexión.</span></div>' : ''}${nota}
        <div id="cuadre-pin" style="display:grid;gap:14px">
          <div><h2 style="font-size:1.4rem;margin:0">¿Quién entra?</h2><p class="muted" style="margin-top:4px">${esc(subtitulo)} · Equipo <b>${esc(E.equipo(tipo).nombre)}</b></p></div>
          <div style="display:grid;gap:8px">${conPin.map(p => `<button type="button" class="btn${yo && yo.uid === p.uid ? ' primary' : ''}" data-act="cuadre-quien" data-uid="${esc(p.uid)}" ${p.bloqueado || p.vencido ? 'disabled' : ''} style="display:flex;justify-content:space-between;gap:10px;text-align:left">
            <span><b>${esc(p.nombre)}</b> <span class="small">${esc(p.rol)}</span></span>${p.bloqueado ? '<span class="small">Bloqueado: entra con tu clave</span>' : p.vencido ? '<span class="small">Vencido: entra con tu clave</span>' : ''}</button>`).join('')}</div>
          ${yo ? `<form id="pinForm" style="display:grid;gap:10px"><div class="field"><label for="lpin">PIN de ${esc(yo.nombre)}</label>
            <input id="lpin" class="input" type="password" inputmode="numeric" pattern="[0-9]*" maxlength="6" autocomplete="off" required></div>
            <p id="login-err" class="small" role="alert" style="color:var(--bad,#b3261e);margin:0" ${api.pinErr ? '' : 'hidden'}>${esc(api.pinErr)}</p>
            <button class="btn primary big" type="submit">Entrar</button></form>`
            : `<p class="small muted" style="margin:0">Toca tu nombre para escribir tu PIN.</p>${api.pinErr ? `<p id="login-err" class="small" role="alert" style="color:var(--bad,#b3261e);margin:0">${esc(api.pinErr)}</p>` : ''}`}
          <button type="button" class="btn sm" data-act="cuadre-con-clave" style="justify-self:start">Entrar con correo y clave</button></div>`;
      }
      return `${aviso}${nota}<form id="loginForm">
      <div><h2 style="font-size:1.4rem">Iniciar sesión</h2><p class="muted" style="margin-top:4px">${esc(subtitulo)}</p></div>
      <div class="field"><label for="lu">Correo</label><input id="lu" class="input" type="email" autocomplete="username" required></div>
      <div class="field"><label for="lp">Clave</label><input id="lp" class="input" type="password" autocomplete="current-password" required></div>
      <p id="login-err" class="small" role="alert" style="color:var(--bad,#b3261e);margin:0" hidden></p>
      <button class="btn primary big" type="submit">Entrar</button>
      <button type="button" class="btn sm" data-act="cuadre-olvide" style="justify-self:start">Olvidé mi clave</button>
      ${conPin.length ? '<button type="button" class="btn sm" data-act="cuadre-con-pin" style="justify-self:start">Entrar con PIN</button>' : ''}
    </form>`;
    },

    async entrar(tipo, correo, clave) {
      if (!listo) throw new Error('El sistema todavía no está conectado a la base de datos.');
      const {error} = await db.auth.signInWithPassword({email: correo.trim().toLowerCase(), password: clave});
      if (error) throw error;
      try { return await acceso(tipo); } catch (e) { await db.auth.signOut(); throw e; }
    },

    /* Al abrir la página: si ya hay sesión en este equipo, entra solo */
    async sesion(tipo) {
      if (!listo) return null;
      const crudo = sesionGuardada(), E = EQ();
      // Sin internet: el rol que quedó guardado en el equipo para esa misma persona
      const local = () => {
        const r = crudo && E && E.registro(tipo, crudo.user.id); if (r) return {...r.acceso, sinConexion: true};
        try { const c = JSON.parse(localStorage.getItem(cache(tipo)) || 'null'); if (c && crudo && (!c.uid || c.uid === crudo.user.id)) return {...c, sinConexion: true}; } catch (_) {}
        return null;
      };
      if (!crudo) return null;
      if (!navigator.onLine) return local();
      const {data} = await db.auth.getSession();
      if (!data.session) return errorDeRed() ? local() : null;
      try { const a = await acceso(tipo); if (E && E.tienePin(tipo, data.session.user.id)) E.confirmar(tipo, data.session.user.id, a); return a; }
      catch (e) { if (errorDeRed(e)) return local(); if (E) E.quitar(tipo, data.session.user.id); return null; }
    },

    /* Salir. En un equipo con PIN, la sesión de esa persona queda guardada (cifrada) para volver con el PIN.
       Si no, se cierra solo en este equipo: la persona sigue dentro en sus otros equipos (su celular, la caja) */
    async salir(tipo) {
      try { localStorage.removeItem(cache(tipo)); } catch (_) {}
      api.acceso = null; api.quien = null; api.modoClave = false; api.pinErr = ''; api.pidePin = null;
      if (!listo) return;
      const s = sesionGuardada(), E = EQ(), reg = s && E && E.registro(tipo, s.user.id);
      if (reg && E.sid(s) === reg.sid) {
        try { localStorage.removeItem(K_SESION); } catch (_) {}
        if (E.reanudar(tipo, s.user.id)) await E.guardarSesion(s);
        E.soltar(); return;
      }
      if (E) E.soltar();
      if (s && navigator.onLine) await db.auth.signOut({scope: 'local'}).catch(() => {});
      try { localStorage.removeItem(K_SESION); } catch (_) {}
    },
    /* Usuarios → Este equipo: quien está dentro crea su PIN */
    async crearMiPin(pin) {
      const s = sesionGuardada(), E = EQ();
      if (!s || !E || !api.acceso) throw new Error('Vuelve a entrar con tu correo y tu clave');
      await E.crearPin(api._tipo, pin, s, api.acceso);
    },

    /* Conecta la pantalla de entrada de un sistema.
       op.tipo: 'farmacia' | 'laboratorio' | 'crossfit'
       op.abrir(acceso): pone el rol y el nombre en el estado y abre la primera pantalla */
    montar(op) {
      api._tipo = op.tipo;
      const err = t => { const p = document.getElementById('login-err'); if (p) { p.textContent = t; p.hidden = !t; } };
      /* Cada apertura lleva su turno. El formulario (correo y clave) siempre gana: si a la vez se
         estaba abriendo la sesión guardada de otro usuario, esa apertura vieja se descarta. */
      let turno = 0;
      const repintar = () => { if (typeof render === 'function') try { render(); } catch (_) {} };
      const abrir = async (a, t) => {
        if (t !== turno) return;
        api.acceso = {...a, tipo: op.tipo};
        for (const f of [...new Set(ganchos.map(g => g.fase))].sort((x, y) => x - y)) {
          if (t !== turno) return;
          await Promise.all(ganchos.filter(g => g.fase === f).map(g => Promise.resolve().then(() => g.fn(api.acceso)).catch(x => console.error('Cuadre: al entrar', x))));
        }
        if (t !== turno) return;
        api.restaurando = false; api.notaEntrada = ''; marcarActividad(true);
        op.abrir(a);
      };

      /* Cierre por inactividad: 30 minutos sin tocar el sistema (en cualquier pestaña).
         Recargar la página no cuenta como inactividad. Sin internet no se cierra, para no dejar
         la caja fuera cuando hace falta conexión para volver a entrar. */
      const LIMITE = 30 * 60 * 1000, CLAVE = 'cuadre.actividad';
      const ultima = () => { try { return +localStorage.getItem(CLAVE) || 0; } catch (_) { return 0; } };
      let marcada = 0;
      function marcarActividad(ya) { const ahora = Date.now(); if (!ya && ahora - marcada < 15000) return; marcada = ahora; try { localStorage.setItem(CLAVE, String(ahora)); } catch (_) {} }
      ['click', 'keydown', 'pointermove', 'touchstart', 'scroll', 'wheel'].forEach(ev => window.addEventListener(ev, () => { if (api.acceso) marcarActividad(); }, {passive: true, capture: true}));
      const conPinAhora = () => !!(EQ() && EQ().activo());
      const cerrarPorInactividad = async () => {
        ++turno; api.restaurando = false;
        api.notaEntrada = conPinAhora() ? 'Pasaron 30 minutos sin uso: escribe tu PIN para seguir.' : 'Tu sesión se cerró por 30 minutos sin uso. Vuelve a entrar con tu correo y tu clave.';
        const p = api.salir(op.tipo);
        if (typeof go === 'function') go('login'); else repintar();
        await p;
      };
      // Con PIN se bloquea aunque no haya internet (se vuelve a entrar con el PIN sin conexión)
      setInterval(() => { if (api.acceso && (navigator.onLine || conPinAhora()) && ultima() && Date.now() - ultima() > LIMITE) cerrarPorInactividad(); }, 30000);

      document.addEventListener('click', e => {
        if (!e.target.closest('[data-act="cuadre-otra"]')) return;
        ++turno; api.restaurando = false; repintar();   // deja de abrir la sesión guardada y muestra el formulario
      }, true);

      document.addEventListener('submit', async e => {
        if (e.target.id !== 'loginForm') return;
        e.preventDefault(); e.stopImmediatePropagation();
        const b = e.target.querySelector('[type=submit]');
        err(''); b.disabled = true; b.textContent = 'Entrando…';
        const t = ++turno; api.restaurando = false;   // lo escrito manda sobre cualquier sesión guardada que se esté abriendo
        try {
          const a = await api.entrar(op.tipo, document.getElementById('lu').value, document.getElementById('lp').value);
          if (t !== turno) return;
          const E = EQ(), s = sesionGuardada();
          // Equipo registrado y la persona sin PIN aquí: se le ofrece crearlo antes de abrir
          if (usaPin(op.tipo) && s && a.rol !== 'socio' && !E.tienePin(op.tipo, s.user.id)) { api.pidePin = {a, t}; repintar(); return; }
          if (E && s && E.tienePin(op.tipo, s.user.id)) E.confirmar(op.tipo, s.user.id, a);   // entró con su clave: se desbloquea y cuenta los 7 días
          await abrir(a, t);
        }
        catch (x) { err(msg(x)); b.disabled = false; b.textContent = 'Entrar'; }
      }, true);

      /* PIN nuevo después de entrar con la clave */
      document.addEventListener('submit', async e => {
        if (e.target.id !== 'pinNuevo') return;
        e.preventDefault(); e.stopImmediatePropagation();
        const p1 = document.getElementById('pin1').value, p2 = document.getElementById('pin2').value, b = e.target.querySelector('[type=submit]');
        if (p1 !== p2) { err('Los dos PIN no son iguales'); return; }
        b.disabled = true;
        try { const {a, t} = api.pidePin; await EQ().crearPin(op.tipo, p1, sesionGuardada(), a); api.pidePin = null; if (t === turno) await abrir(a, t); }
        catch (x) { err(msg(x)); b.disabled = false; }
      }, true);

      /* Entrada con PIN: con internet confirma el acceso en la base; sin internet abre con lo guardado */
      document.addEventListener('submit', async e => {
        if (e.target.id !== 'pinForm') return;
        e.preventDefault(); e.stopImmediatePropagation();
        const E = EQ(), uid = api.quien, b = e.target.querySelector('[type=submit]');
        b.disabled = true; b.textContent = 'Entrando…';
        const t = ++turno; api.restaurando = false; api.pinErr = '';
        try {
          const r = await E.entrar(op.tipo, uid, document.getElementById('lpin').value);
          localStorage.setItem(K_SESION, JSON.stringify(r.sesion));
          db.auth.startAutoRefresh().catch(() => {});
          // Abre de una vez con el rol guardado; con internet, la base confirma el acceso a la vez que se cargan los datos
          const a = {...r.acceso, sinConexion: !navigator.onLine};
          if (navigator.onLine) acceso(op.tipo).then(n => {
            E.confirmar(op.tipo, uid, n);
            if (n.rol !== a.rol || n.empresa_id !== a.empresa_id) location.reload();   // le cambiaron el rol: abre de nuevo con el nuevo
          }).catch(async x => {
            if (errorDeRed(x)) { if (api.acceso) api.acceso.sinConexion = true; return; }
            E.quitar(op.tipo, uid); ++turno;
            api.notaEntrada = 'Tu PIN ya no sirve en este equipo: cambió tu acceso. Entra con tu correo y tu clave.';
            const p = api.salir(op.tipo); if (typeof go === 'function') go('login'); else repintar(); await p;
          });
          api.quien = null; api.notaEntrada = '';
          if (t === turno) await abrir(a, t);
        } catch (x) {
          api.pinErr = msg(x);
          const p = E.registro(op.tipo, uid); if (!p || p.intentos >= E.INTENTOS) api.quien = null;
          repintar(); const i = document.getElementById('lpin'); if (i) i.focus();
        }
      }, true);

      document.addEventListener('click', e => {
        const q = e.target.closest('[data-act="cuadre-quien"],[data-act="cuadre-con-clave"],[data-act="cuadre-con-pin"],[data-act="cuadre-sin-pin"]'); if (!q) return;
        e.preventDefault(); e.stopImmediatePropagation();
        const act = q.dataset.act;
        if (act === 'cuadre-quien') { api.quien = q.dataset.uid; api.pinErr = ''; repintar(); const i = document.getElementById('lpin'); if (i) i.focus(); }
        else if (act === 'cuadre-con-clave') { api.modoClave = true; api.pinErr = ''; repintar(); }
        else if (act === 'cuadre-con-pin') { api.modoClave = false; repintar(); }
        else if (act === 'cuadre-sin-pin' && api.pidePin) { const {a, t} = api.pidePin; api.pidePin = null; if (t === turno) abrir(a, t); }
      }, true);

      /* Volvió internet después de entrar sin conexión: la base confirma que esa persona sigue teniendo acceso */
      window.addEventListener('online', async () => {
        const a = api.acceso, E = EQ(); if (!a || !a.sinConexion || !listo) return;
        const s = sesionGuardada(); if (!s) return;
        try { const n = await acceso(op.tipo); if (E && E.tienePin(op.tipo, s.user.id)) E.confirmar(op.tipo, s.user.id, n); a.sinConexion = false; }
        catch (x) {
          if (errorDeRed(x)) return;
          if (E) E.quitar(op.tipo, s.user.id);
          ++turno; api.notaEntrada = 'Tu acceso a este negocio cambió. Entra con tu correo y tu clave.';
          const p = api.salir(op.tipo); if (typeof go === 'function') go('login'); else repintar(); await p;
        }
      });

      document.addEventListener('click', async e => {
        if (!e.target.closest('[data-act="cuadre-olvide"]')) return;
        const correo = (document.getElementById('lu').value || '').trim();
        if (!correo) { err('Escribe tu correo y vuelve a tocar «Olvidé mi clave»'); return; }
        if (!listo) { err('El sistema todavía no está conectado a la base de datos.'); return; }
        const {error} = await db.auth.resetPasswordForEmail(correo, {redirectTo: location.href.split('#')[0]});
        err(error ? msg(error) : 'Te enviamos un correo para poner una clave nueva.');
      }, true);

      if (listo) db.auth.onAuthStateChange(async (ev, ses) => {
        // Supabase renovó la sesión: si es de quien entró con PIN, se guarda la nueva (cifrada)
        if ((ev === 'TOKEN_REFRESHED' || ev === 'SIGNED_IN') && ses && EQ()) { EQ().guardarSesion(ses).catch(() => {}); return; }
        if (ev !== 'PASSWORD_RECOVERY') return;
        const nueva = prompt('Escribe tu clave nueva (mínimo 8 caracteres)');
        if (!nueva || nueva.length < 8) { alert('La clave no se cambió.'); return; }
        const {error} = await db.auth.updateUser({password: nueva});
        alert(error ? msg(error) : 'Listo, tu clave quedó cambiada.');
      });

      const iniciar = async () => {
        const t = ++turno;
        if (!listo) return;
        const crudo = sesionGuardada(), E = EQ();
        if (!crudo) { repintar(); return; }
        const reg = E && usaPin(op.tipo) && E.registro(op.tipo, crudo.user.id);
        if (reg && E.sid(crudo) === reg.sid && !E.reanudar(op.tipo, crudo.user.id)) {
          // App recién abierta (o una pestaña nueva) en un equipo con PIN: se pide el PIN. La sesión abierta
          // no se toca (puede estar en uso en otra pestaña); esta pestaña no la renueva hasta que entre el PIN
          db.auth.stopAutoRefresh().catch(() => {});
          repintar(); return;
        }
        // Sesión guardada, pero vencida por inactividad: se cierra en vez de abrirla (con PIN: se pide el PIN)
        if ((navigator.onLine || (E && E.activo())) && ultima() && Date.now() - ultima() > LIMITE) {
          api.notaEntrada = E && E.activo() ? 'Pasaron 30 minutos sin uso: escribe tu PIN para seguir.' : 'Tu sesión se cerró por 30 minutos sin uso. Vuelve a entrar con tu correo y tu clave.';
          await api.salir(op.tipo); repintar(); return;
        }
        if (t !== turno) return;
        api.restaurando = true; repintar();   // «Abriendo tu sesión…» en vez del formulario
        const a = await api.sesion(op.tipo);
        if (a && t === turno) await abrir(a, t);
        else if (t === turno) { api.restaurando = false; repintar(); }
      };
      // Apenas están todos los archivos (sin esperar fuentes ni imágenes)
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', iniciar); else setTimeout(iniciar, 0);
    },

    /* A qué pantalla ir después de entrar: la del enlace (#vista) si el rol la puede ver */
    ir(puede, porDefecto) {
      const v = api.destino; api.destino = '';
      return v && puede(v) ? v : porDefecto;
    }
  };
  return api;
})();
