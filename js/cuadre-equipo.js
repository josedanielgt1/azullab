/* =====================================================================
   Cuadre · Equipo registrado y entrada con PIN
   Un equipo de uso fijo (la caja, la recepción) lo registra el dueño o el
   gerente. Cada persona entra una vez con correo y clave y crea su PIN para
   ese equipo; desde ahí entra solo con el PIN, con o sin internet.

   Qué se guarda en el equipo, por persona:
     * Su sesión de Supabase, cifrada (AES-GCM) con una llave que sale del
       PIN (PBKDF2-SHA256, 310 000 vueltas). Sin el PIN no se puede leer.
     * Una huella del PIN para comprobarlo (no el PIN).
     * Su rol y su nombre, para abrir sin internet.
   Reglas: 5 PIN errados bloquean a esa persona en este equipo; 7 días sin
   conectarse vencen el PIN. En los dos casos se vuelve a entrar con la clave.
   Necesita https (o localhost): el navegador solo cifra en sitios seguros.
   ===================================================================== */
window.CuadreEquipo = (() => {
  const VUELTAS = 310000, INTENTOS = 5, VENCE = 7 * 864e5;
  const te = new TextEncoder(), td = new TextDecoder();
  const b64 = buf => btoa(String.fromCharCode(...new Uint8Array(buf)));
  const deB64 = s => Uint8Array.from(atob(s), c => c.charCodeAt(0));
  const leer = k => { try { return JSON.parse(localStorage.getItem(k) || 'null'); } catch (_) { return null; } };
  const escribir = (k, v) => { try { v == null ? localStorage.removeItem(k) : localStorage.setItem(k, JSON.stringify(v)); } catch (_) {} };
  const kEquipo = t => 'cuadre.equipo.' + t, kPines = t => 'cuadre.pines.' + t, K_ACTIVO = 'cuadre.pinActivo';
  const pines = t => leer(kPines(t)) || {};
  const disponible = () => !!(window.crypto && crypto.subtle && window.isSecureContext);

  /* El id de la sesión va dentro del token: sirve para saber si la sesión abierta es la misma que la guardada */
  const sid = s => { try { const p = JSON.parse(atob(s.access_token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))); return p.session_id || p.sub || ''; } catch (_) { return ''; } };

  async function derivar(pin, sal) {
    const base = await crypto.subtle.importKey('raw', te.encode(pin), 'PBKDF2', false, ['deriveBits']);
    const bits = new Uint8Array(await crypto.subtle.deriveBits({name: 'PBKDF2', hash: 'SHA-256', salt: sal, iterations: VUELTAS}, base, 512));
    return {huella: b64(bits.slice(0, 32)), llave: bits.slice(32)};
  }
  async function cifrar(llaveBytes, obj) {
    const k = await crypto.subtle.importKey('raw', llaveBytes, 'AES-GCM', false, ['encrypt']);
    const iv = crypto.getRandomValues(new Uint8Array(12));
    return {iv: b64(iv), datos: b64(await crypto.subtle.encrypt({name: 'AES-GCM', iv}, k, te.encode(JSON.stringify(obj))))};
  }
  async function descifrar(llaveBytes, c) {
    const k = await crypto.subtle.importKey('raw', llaveBytes, 'AES-GCM', false, ['decrypt']);
    return JSON.parse(td.decode(await crypto.subtle.decrypt({name: 'AES-GCM', iv: deB64(c.iv)}, k, deB64(c.datos))));
  }
  const iguales = (a, b) => { if (a.length !== b.length) return false; let d = 0; for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i); return d === 0; };

  /* Quién entró con PIN en esta ventana: su llave vive en sessionStorage (se borra al cerrar la app),
     así recargar no pide el PIN otra vez y cada sesión renovada se vuelve a guardar cifrada */
  let activo = null;
  const ponerActivo = (t, uid, llave) => { activo = {tipo: t, uid, llave}; try { sessionStorage.setItem(K_ACTIVO, JSON.stringify({tipo: t, uid, k: b64(llave)})); } catch (_) {} };

  const E = {
    disponible, sid, INTENTOS,
    equipo: t => leer(kEquipo(t)),
    registrar(t, nombre, quien) { escribir(kEquipo(t), {nombre: String(nombre).trim().slice(0, 40), registrado: new Date().toISOString(), por: quien}); },
    quitarEquipo(t) { escribir(kEquipo(t), null); escribir(kPines(t), null); E.soltar(); },

    /* Las personas con PIN en este equipo, para la pantalla «¿Quién entra?» */
    personas(t) {
      return Object.values(pines(t)).map(p => ({uid: p.uid, nombre: p.nombre, rol: p.rolTxt, ultima: p.ultima,
        bloqueado: p.intentos >= INTENTOS, vencido: Date.now() - p.ultima > VENCE})).sort((a, b) => a.nombre.localeCompare(b.nombre));
    },
    registro: (t, uid) => pines(t)[uid] || null,
    tienePin: (t, uid) => !!pines(t)[uid],

    async crearPin(t, pin, sesion, acceso) {
      if (!/^\d{4,6}$/.test(pin)) throw new Error('El PIN son de 4 a 6 números');
      if (/^(\d)\1+$/.test(pin) || '0123456789'.includes(pin) || '9876543210'.includes(pin)) throw new Error('Ese PIN es muy fácil de adivinar: no uses números repetidos ni seguidos');
      const uid = sesion.user.id, sal = crypto.getRandomValues(new Uint8Array(16)), {huella, llave} = await derivar(pin, sal);
      const todos = pines(t);
      todos[uid] = {uid, nombre: acceso.nombre || sesion.user.email, correo: sesion.user.email, rolTxt: acceso.rolTxt, acceso,
        sal: b64(sal), huella, sid: sid(sesion), ...(await cifrar(llave, sesion)), intentos: 0, ultima: Date.now(), creado: Date.now()};
      escribir(kPines(t), todos); ponerActivo(t, uid, llave);
    },

    /* Comprueba el PIN y devuelve la sesión guardada y el rol. Lanza el mensaje para la pantalla si no */
    async entrar(t, uid, pin) {
      const todos = pines(t), p = todos[uid];
      if (!p) throw new Error('Esa persona no tiene PIN en este equipo');
      if (p.intentos >= INTENTOS) throw new Error('PIN bloqueado por intentos fallidos: entra con tu correo y tu clave');
      if (Date.now() - p.ultima > VENCE) throw new Error('Pasaron más de 7 días sin conexión: entra con tu correo y tu clave');
      const {huella, llave} = await derivar(pin, deB64(p.sal));
      if (!iguales(huella, p.huella)) {
        p.intentos++; escribir(kPines(t), todos);
        const q = INTENTOS - p.intentos;
        throw new Error(q > 0 ? `PIN incorrecto. Te ${q === 1 ? 'queda 1 intento' : 'quedan ' + q + ' intentos'}` : 'PIN bloqueado por intentos fallidos: entra con tu correo y tu clave');
      }
      p.intentos = 0; escribir(kPines(t), todos);
      const sesion = await descifrar(llave, p);
      ponerActivo(t, uid, llave);
      return {sesion, acceso: p.acceso};
    },

    /* Supabase renovó la sesión de quien está con PIN: se guarda la nueva, cifrada */
    async guardarSesion(sesion) {
      if (!activo || !sesion || !sesion.user || sesion.user.id !== activo.uid) return;
      const {tipo: t, uid} = activo, c = await cifrar(activo.llave, sesion);
      // Se lee después de cifrar: si mientras tanto le quitaron el PIN, no se revive
      const todos = pines(t), p = todos[uid]; if (!p || !activo || activo.uid !== uid) return;
      Object.assign(p, c, {sid: sid(sesion)}); escribir(kPines(t), todos);
    },
    /* Con internet la base confirmó el acceso: cuenta los 7 días desde ahora y guarda el rol al día */
    confirmar(t, uid, acceso) {
      const todos = pines(t), p = todos[uid]; if (!p) return;
      Object.assign(p, {ultima: Date.now(), intentos: 0, acceso, rolTxt: acceso.rolTxt, nombre: acceso.nombre || p.nombre}); escribir(kPines(t), todos);
    },
    quitar(t, uid) { const todos = pines(t); delete todos[uid]; escribir(kPines(t), todos); if (activo && activo.uid === uid) E.soltar(); },

    /* Después de recargar: recupera la llave de quien estaba con PIN en esta ventana */
    reanudar(t, uid) {
      if (activo && activo.tipo === t && activo.uid === uid) return true;
      const a = (() => { try { return JSON.parse(sessionStorage.getItem(K_ACTIVO) || 'null'); } catch (_) { return null; } })();
      if (a && a.tipo === t && a.uid === uid && pines(t)[uid]) { activo = {tipo: t, uid, llave: deB64(a.k)}; return true; }
      return false;
    },
    activo: () => activo,
    soltar() { activo = null; try { sessionStorage.removeItem(K_ACTIVO); } catch (_) {} }
  };
  return E;
})();
