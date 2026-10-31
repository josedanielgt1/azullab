/* =====================================================================
   Cuadre · Acceso común de los sistemas del Grupo Azullab
   Se entra con correo y clave (Supabase Auth). El sistema busca en la
   base el rol de esa persona en este negocio y abre sus pantallas:
   nadie escoge su rol en la entrada.
   Necesita, antes de este archivo:
     <script src="js/vendor/supabase-2.118.0.js"></script>   (copia local: abre sin internet)
     <script src="js/config.js"></script>
   ===================================================================== */
window.Cuadre = (() => {
  const C = window.CUADRE_CONFIG || {};
  const listo = !!(C.url && C.key && window.supabase);
  const db = listo ? window.supabase.createClient(C.url, C.key, {auth: {persistSession: true, storageKey: 'cuadre.sesion'}}) : null;

  /* Rol de la base → nombre del rol en cada sistema (las llaves de ROLES en cada HTML) */
  const ROLES = {
    farmacia:    {dueno: 'Dueño', gerente: 'Dueño', regente: 'Farmacéutico', cajero: 'Cajero', almacen: 'Almacén'},
    laboratorio: {dueno: 'Dueño', gerente: 'Dueño', bioanalista: 'Bioanalista', atencion: 'Atención', toma_muestras: 'Toma de muestras'},
    crossfit:    {dueno: 'Dueño', gerente: 'Dueño', coach: 'Coach'}
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

  const api = {
    listo, db, destino: '', acceso: null,

    /* El formulario de entrada (lo mismo en los tres sistemas) */
    formulario(subtitulo) {
      const aviso = !listo
        ? '<div class="aviso-off" role="status"><span><b>Falta conectar la base de datos.</b> Copia la URL y la clave pública de Supabase en <code>js/config.js</code>.</span></div>'
        : !navigator.onLine
          ? '<div class="aviso-off" role="status"><span><b>Sin internet.</b> Si ya entraste antes en este equipo, el sistema abre con la sesión guardada. La primera vez hace falta conexión.</span></div>'
          : '';
      return `${aviso}<form id="loginForm">
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
      const abrir = a => { api.acceso = a; op.abrir(a); };

      document.addEventListener('submit', async e => {
        if (e.target.id !== 'loginForm') return;
        e.preventDefault(); e.stopImmediatePropagation();
        const b = e.target.querySelector('[type=submit]');
        err(''); b.disabled = true; b.textContent = 'Entrando…';
        try { abrir(await api.entrar(op.tipo, document.getElementById('lu').value, document.getElementById('lp').value)); }
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

      const iniciar = async () => { const a = await api.sesion(op.tipo); if (a) abrir(a); };
      if (document.readyState === 'complete') iniciar(); else window.addEventListener('load', iniciar);
    },

    /* A qué pantalla ir después de entrar: la del enlace (#vista) si el rol la puede ver */
    ir(puede, porDefecto) {
      const v = api.destino; api.destino = '';
      return v && puede(v) ? v : porDefecto;
    }
  };
  return api;
})();
