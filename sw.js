/* Cuadre · Guarda los archivos del sistema en el equipo para que abra sin internet.
   Primero intenta la red (para tener siempre la última versión); si no hay, usa la copia. */
const CACHE = 'cuadre-v3';
const ARCHIVOS = ['./', 'index.html', 'farmacia.html', 'laboratorio.html', 'crossfit.html',
  'js/config.js', 'js/cuadre-equipo.js', 'js/cuadre.js', 'js/cuadre-comun.js', 'js/farmacia-real.js', 'js/laboratorio-real.js', 'js/crossfit-real.js',
  'js/vendor/supabase-2.118.0.js', 'assets/logo-azullab.png',
  'manifest-farmacia.webmanifest', 'manifest-laboratorio.webmanifest', 'manifest-crossfit.webmanifest',
  'assets/iconos/icono-192.png', 'assets/iconos/icono-512.png', 'assets/iconos/icono-192-maskable.png', 'assets/iconos/icono-512-maskable.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(ARCHIVOS)).then(() => self.skipWaiting())); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', e => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.origin !== location.origin) return;   // la base de datos va siempre por la red
  // cache 'no-cache': siempre pregunta al servidor si hay versión nueva (si no cambió, la respuesta es mínima)
  e.respondWith(fetch(e.request, {cache: 'no-cache'}).then(r => { const copia = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copia)); return r; })
    .catch(() => caches.match(e.request, {ignoreSearch: true})));
});
