// Lo hecho sin internet: aviso, copia en carpeta, recuperación desde el archivo y subida (Supabase simulado)
const { chromium } = require('playwright'); const mock = require('./mock');
(async () => {
  const b = await chromium.launch(); let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
  const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Caracas' }).format(new Date());
  const ctx = await b.newContext(); const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message + ' @ ' + (e.stack || '').split('\n').slice(1, 4).join(' | ')));
  const rest = async (st, { m, p }) => { if (m === 'GET' && p.startsWith('/rest/v1/') && !p.includes('/rpc/')) return { body: [] }; };   // base vacía
  const st = mock(pg, { tasas: [{ fecha: hoy, tasa: 100 }], rest });
  await pg.goto('http://localhost:8765/farmacia.html'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'x'); await pg.click('#loginForm [type=submit]');
  await pg.waitForFunction(() => S.view !== 'login');
  const ARCH = 'cuadre-farmacia-pendientes.json';
  // Carpeta de mentira (la real la escoge la persona con el selector de Chrome)
  await pg.evaluate(() => {
    window.__archivos = {};
    Cuadre.respaldo.manija = { name: 'Cuadre-respaldo', queryPermission: async () => 'granted', requestPermission: async () => 'granted',
      getFileHandle: async n => ({ createWritable: async () => ({ write: async d => { window.__archivos[n] = d; }, close: async () => {} }) }),
      removeEntry: async n => { delete window.__archivos[n]; } };
  });
  await ctx.setOffline(true);
  const venta = { numero: 900000007, maquina: 'Z7C0012345', fecha: new Date().toISOString(), cliente: { rif: 'V-00000000', nombre: 'Consumidor final' }, items: [{ producto_id: 1, cantidad: 1, precio_usd: 2 }], pagos: [{ metodo: 'Efectivo Bs', monto_bs: 200, divisa: false }], usuario: 'José Guerrero' };
  await pg.evaluate(v => Cuadre.guardarLocal('cola', [v]), venta);
  await pg.waitForFunction(n => window.__archivos[n], ARCH, { timeout: 5000 }).catch(() => {});
  ok((await pg.textContent('#cuadre-pendientes')).includes('1 venta sin subir'), 'con una venta sin subir, una franja avisa que no se cierre ni se borre el navegador');
  const copia = await pg.evaluate(n => JSON.parse(window.__archivos[n] || 'null'), ARCH);
  ok(copia && copia.cola.length === 1 && copia.cola[0].numero === 900000007 && copia.empresa_id === 'E', 'la venta queda copiada en la carpeta del equipo');
  ok((await pg.textContent('#cuadre-pendientes')).includes('copia en la carpeta'), 'la franja dice que hay copia en la carpeta');

  // Alguien borra los datos del navegador: la venta ya no está en el equipo
  await pg.evaluate(() => localStorage.removeItem('cuadre.farmacia.cola'));
  await pg.evaluate(() => go('equipo'));
  ok((await pg.textContent('main')).includes('Respaldo de lo hecho sin internet'), '«Este equipo» muestra el respaldo');
  await pg.setInputFiles('#eq-recuperar', { name: ARCH, mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(copia)) });
  await pg.waitForFunction(() => document.body.textContent.includes('recuperad'), null, { timeout: 5000 }).catch(() => {});
  ok(await pg.evaluate(() => (JSON.parse(localStorage.getItem('cuadre.farmacia.cola') || '[]')).length === 1), 'desde el archivo, la venta vuelve al equipo');
  await pg.setInputFiles('#eq-recuperar', { name: ARCH, mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(copia)) });
  await pg.waitForTimeout(300);
  ok(await pg.evaluate(() => (JSON.parse(localStorage.getItem('cuadre.farmacia.cola') || '[]')).length === 1), 'recuperar dos veces el mismo archivo no repite la venta');
  await pg.setInputFiles('#eq-recuperar', { name: 'otro.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify({ ...copia, tipo: 'laboratorio', empresa: 'Azullab Laboratorio' })) });
  await pg.waitForFunction(() => document.body.textContent.includes('es de Azullab Laboratorio'), null, { timeout: 3000 }).catch(() => {});
  ok((await pg.textContent('body')).includes('es de Azullab Laboratorio'), 'un respaldo de otro negocio no se mezcla');
  await pg.setInputFiles('#eq-recuperar', { name: 'x.json', mimeType: 'application/json', buffer: Buffer.from('hola') });
  await pg.waitForFunction(() => document.body.textContent.includes('no es un respaldo'), null, { timeout: 3000 }).catch(() => {});
  ok((await pg.textContent('body')).includes('no es un respaldo de Cuadre'), 'un archivo cualquiera no se acepta');

  // Vuelve internet: sube, se borra el archivo y se quita la franja
  await ctx.setOffline(false); await pg.evaluate(() => window.dispatchEvent(new Event('online')));
  await pg.waitForFunction(() => !document.getElementById('cuadre-pendientes'), null, { timeout: 10000 }).catch(() => {});
  ok(st.llamadas.some(l => l.p === '/rest/v1/rpc/vender_impresa' && l.b.p_numero === 900000007 && l.b.p_registro === 'Z7C0012345'), 'al volver internet, la venta recuperada sube a la base con su número de la máquina fiscal');
  ok(!(await pg.$('#cuadre-pendientes')), 'ya subida, la franja se quita');
  ok(await pg.evaluate(n => !window.__archivos[n], ARCH), 'y el archivo de la carpeta se borra');
  ok(errs.length === 0, 'sin errores en la página' + (errs.length ? ': ' + errs.join(' | ').slice(0, 300) : ''));
  await b.close(); process.exit(fallas ? 1 : 0);
})();
