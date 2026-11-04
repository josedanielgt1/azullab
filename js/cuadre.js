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
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));

  async function acceso(tipo) {
    const {data, error} = await db.rpc('mi_acceso', {p_tipo: tipo});
    if (error) throw error;
    const a = data && data[0];
    if (!a) throw new Error('Tu usuario no tiene un rol en este negocio. Pídele al dueño que te lo asigne.');
    const rol = ROLES[tipo][a.rol];
    if (!rol) throw new Error('Tu rol no tiene pantallas en este sistema.');
    const r = {...a, rolTxt: rol};
    try { localStorage.setItem(cache(tipo), JSON.stringify(r)); } catch (_) {}
    return r;
  }

  const ganchos = [];
  const api = {
    listo, db, destino: '', acceso: null, ROLES, msg, esc, neutro,
    /* Lo que se carga de la base al entrar, antes de abrir la primera pantalla */
    alEntrar(fn) { ganchos.push(fn); },

    /* El formulario de entrada (lo mismo en los tres sistemas) */
    formulario(subtitulo) {
      const aviso = !listo
        ? '<div class="aviso-off" role="status"><span><b>Falta conectar la base de datos.</b> Copia la URL y la clave pública de Supabase en <code>js/config.js</code>.</span></div>'
        : !navigator.onLine
          ? '<div class="aviso-off" role="status"><span><b>Sin internet.</b> Si ya entraste antes en este equipo, el sistema abre con la sesión guardada. La primera vez hace falta conexión.</span></div>'
          : '';
      if (api.restaurando) return `<div id="cuadre-abriendo" style="display:grid;gap:12px;justify-items:start" role="status">
        <h2 style="font-size:1.4rem;margin:0">Abriendo tu sesión…</h2>
        <p class="muted" style="margin:0">${esc(subtitulo)}. Un momento: estamos cargando tus datos.</p>
        <button type="button" class="btn sm" data-act="cuadre-otra">Entrar con otra cuenta</button></div>`;
      const nota = api.notaEntrada ? `<div class="aviso-off" role="status"><span>${esc(api.notaEntrada)}</span></div>` : '';
      return `${aviso}${nota}<form id="loginForm">
      <div><h2 style="font-size:1.4rem">Iniciar sesión</h2><p class="muted" style="margin-top:4px">${esc(subtitulo)}</p></div>
      <div class="field"><label for="lu">Correo</label><input id="lu" class="input" type="email" autocomplete="username" required></div>
      <div class="field"><label for="lp">Clave</label><input id="lp" class="input" type="password" autocomplete="current-password" required></div>
      <p id="login-err" class="small" role="alert" style="color:var(--bad,#b3261e);margin:0" hidden></p>
      <button class="btn primary big" type="submit">Entrar</button>
      <button type="button" class="btn sm" data-act="cuadre-olvide" style="justify-self:start">Olvidé mi clave</button>
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
      const {data} = await db.auth.getSession();
      if (!data.session) return null;
      try { return await acceso(tipo); }
      catch (e) {
        if (!navigator.onLine) { try { const c = localStorage.getItem(cache(tipo)); if (c) return {...JSON.parse(c), sinConexion: true}; } catch (_) {} }
        return null;
      }
    },

    async salir(tipo) {
      try { localStorage.removeItem(cache(tipo)); } catch (_) {}
      api.acceso = null;
      if (listo) await db.auth.signOut();
    },

    /* Conecta la pantalla de entrada de un sistema.
       op.tipo: 'farmacia' | 'laboratorio' | 'crossfit'
       op.abrir(acceso): pone el rol y el nombre en el estado y abre la primera pantalla */
    montar(op) {
      const err = t => { const p = document.getElementById('login-err'); if (p) { p.textContent = t; p.hidden = !t; } };
      /* Cada apertura lleva su turno. El formulario (correo y clave) siempre gana: si a la vez se
         estaba abriendo la sesión guardada de otro usuario, esa apertura vieja se descarta. */
      let turno = 0;
      const repintar = () => { if (typeof render === 'function') try { render(); } catch (_) {} };
      const abrir = async (a, t) => {
        if (t !== turno) return;
        api.acceso = {...a, tipo: op.tipo};
        for (const g of ganchos) { if (t !== turno) return; try { await g(api.acceso); } catch (x) { console.error('Cuadre: al entrar', x); } }
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
      const cerrarPorInactividad = async () => {
        ++turno; api.restaurando = false;
        api.notaEntrada = 'Tu sesión se cerró por 30 minutos sin uso. Vuelve a entrar con tu correo y tu clave.';
        await api.salir(op.tipo);
        if (typeof go === 'function') go('login'); else repintar();
      };
      setInterval(() => { if (api.acceso && navigator.onLine && ultima() && Date.now() - ultima() > LIMITE) cerrarPorInactividad(); }, 30000);

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
        try { const a = await api.entrar(op.tipo, document.getElementById('lu').value, document.getElementById('lp').value); if (t === turno) await abrir(a, t); }
        catch (x) { err(msg(x)); b.disabled = false; b.textContent = 'Entrar'; }
      }, true);

      document.addEventListener('click', async e => {
        if (!e.target.closest('[data-act="cuadre-olvide"]')) return;
        const correo = (document.getElementById('lu').value || '').trim();
        if (!correo) { err('Escribe tu correo y vuelve a tocar «Olvidé mi clave»'); return; }
        if (!listo) { err('El sistema todavía no está conectado a la base de datos.'); return; }
        const {error} = await db.auth.resetPasswordForEmail(correo, {redirectTo: location.href.split('#')[0]});
        err(error ? msg(error) : 'Te enviamos un correo para poner una clave nueva.');
      }, true);

      if (listo) db.auth.onAuthStateChange(async ev => {
        if (ev !== 'PASSWORD_RECOVERY') return;
        const nueva = prompt('Escribe tu clave nueva (mínimo 8 caracteres)');
        if (!nueva || nueva.length < 8) { alert('La clave no se cambió.'); return; }
        const {error} = await db.auth.updateUser({password: nueva});
        alert(error ? msg(error) : 'Listo, tu clave quedó cambiada.');
      });

      const iniciar = async () => {
        const t = ++turno;
        if (!listo) return;
        const {data} = await db.auth.getSession();
        if (!data.session) return;
        // Sesión guardada, pero vencida por inactividad: se cierra en vez de abrirla
        if (navigator.onLine && ultima() && Date.now() - ultima() > LIMITE) {
          api.notaEntrada = 'Tu sesión se cerró por 30 minutos sin uso. Vuelve a entrar con tu correo y tu clave.';
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
