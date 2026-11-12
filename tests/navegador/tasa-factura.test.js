// La tasa que trae impresa la factura de la droguería: se escribe en Compras y va así al Libro de Compras
const { chromium } = require('playwright'); const mock = require('./mock');
(async () => {
  const b = await chromium.launch(); let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
  const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Caracas' }).format(new Date());
  const prod = (id, nombre, iva) => ({ id, empresa_id: 'E', activo: true, codigo: '75910' + id, codigos_alt: [], nombre, principio_activo: 'X' + id, laboratorio: 'Lab', presentacion: 'Caja', seccion: 'Otros', iva, costo: id === 1 ? 2 : 6, margen: 30, precio: id === 1 ? 2.6 : 7.8, pmvp: null, por_lote: false, minimo: 1, rx: false, controlado: false, historial: [] });
  const T = { rpc: [], compras: [], productos: [prod(1, 'Losartán', 'E'), prod(2, 'Protector solar', 'G')], proveedores: [{ id: 1, empresa_id: 'E', nombre: 'Cobeca', rif: 'J-12345678-9', credito_dias: 0, activo: true }] };
  const rest = async (st, { m, p, b: body }) => {
    if (p === '/rest/v1/productos' && m === 'GET') return { body: T.productos };
    if (p === '/rest/v1/proveedores' && m === 'GET') return { body: T.proveedores };
    if (p === '/rest/v1/compras' && m === 'GET') return { body: T.compras };
    if (p === '/rest/v1/perfiles') return { body: [{ user_id: 'u-d', nombre: 'José Guerrero' }] };
    if (p === '/rest/v1/rpc/tasa_del_dia') return { body: 365 };
    if (p.startsWith('/rest/v1/rpc/')) T.rpc.push({ f: p.slice(13), body });
    if (p === '/rest/v1/rpc/recibir_factura') { const t = body.p_factura.tasa || 365, usd = body.p_items.reduce((s, i) => s + i.cantidad * i.costo, 0);
      const c = { id: T.compras.length + 1, empresa_id: 'E', proveedor_id: 1, proveedor: 'Cobeca', rif: 'J-12345678-9', tipo: 'FAC', numero: body.p_factura.numero, control: body.p_factura.control, fecha: body.p_factura.fecha, tasa: t, exento_usd: usd, gravable_usd: 0, iva_usd: 0, total_usd: usd, pagado_usd: 0, vence: hoy, datos: {} };
      T.compras.push(c); return { body: c }; }
    if (p.startsWith('/rest/v1/rpc/')) return { body: [] };
    if (m === 'GET') return { body: [] };
  };
  const ctx = await b.newContext({ locale: 'en-US' }); const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message));
  mock(pg, { rol: 'dueno', tasas: [{ fecha: hoy, tasa: 365 }], rest });
  await pg.goto('http://localhost:8765/farmacia.html'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]');
  await pg.waitForFunction(() => (typeof S === 'object' && S.view !== 'login' && P.length === 2), null, { timeout: 8000 });
  const aviso = () => pg.textContent('#toast'), pie = () => pg.evaluate(() => document.getElementById('ft-tot').textContent.replace(/\s+/g, ' '));
  const renglon = async (nombre, lote, cant) => { const i = await pg.evaluate(() => RECV.length);
    await pg.fill('#scan', nombre); await pg.press('#scan', 'Enter'); await pg.waitForSelector(`[data-recv="${i}"][data-f="l"]`);
    await pg.fill(`[data-recv="${i}"][data-f="l"]`, lote); await pg.evaluate(k => { RECV[k].e = '2031-01-31'; }, i);
    await pg.fill(`[data-recv="${i}"][data-f="q"]`, String(cant)); await pg.press(`[data-recv="${i}"][data-f="q"]`, 'Tab'); await pg.waitForTimeout(120); };
  const cargar = async () => { const n = T.rpc.filter(r => r.f === 'recibir_factura').length; await pg.click('[data-act="receive"]');
    const m = await pg.waitForSelector('#modal [data-act="recvok"], #modal [data-act="recv-ok"], #modal .btn.primary', { timeout: 1500 }).catch(() => null); if (m) await m.click();
    await pg.waitForFunction(k => true, n); await pg.waitForTimeout(700); return T.rpc.filter(r => r.f === 'recibir_factura').slice(-1)[0]; };

  await pg.evaluate(() => go('purchases'));
  ok(await pg.evaluate(() => !!document.getElementById('ft')) && (await pie()).includes('Si la dejas vacía, va con la BCV del día de la factura'), 'Compras tiene el campo «Tasa de la factura» y explica qué pasa si se deja vacío');
  await renglon('Losartán', 'A1', 10); await renglon('Protector', 'P1', 5);
  await pg.fill('#fn', '0048213'); await pg.fill('#fc', '00-118204');
  await pg.fill('#ft', '360,50'); await pg.waitForTimeout(100);
  ok((await pie()).includes('$ 54,80') || (await pie()).includes('54,80'), 'muestra el total de la factura en dólares (con el IVA de lo gravado): 54,80');
  ok((await pie()).includes('19.755,40') && (await pie()).includes('360,50'), 'y en bolívares a la tasa escrita (19.755,40), para comparar con el papel');
  ok(await pg.evaluate(() => document.activeElement.id === 'ft'), 'escribir la tasa no repinta la pantalla (no se pierde el cursor)');
  await pg.fill('#ft', 'abc'); await pg.click('[data-act="receive"]'); await pg.waitForTimeout(300);
  const m0 = await pg.$('#modal [data-act]'); if (m0) { const ok0 = await pg.$('#modal .btn.primary'); if (ok0) await ok0.click(); await pg.waitForTimeout(400); }
  ok(/Revisa la tasa de la factura/.test(await aviso()) && T.rpc.every(r => r.f !== 'recibir_factura'), 'una tasa que no es número no se manda');
  await pg.fill('#ft', '360,50');
  let r = await cargar();
  ok(r && r.body.p_factura.tasa === 360.5 && r.body.p_factura.numero === '0048213', 'al cargar, la factura va con la tasa del papel (360,5)');
  ok(await pg.evaluate(() => { const c = FX_SYS.compras()[0]; return c && c.ex === 18025; }), 'en el Libro de Compras los bolívares salen a la tasa guardada con la factura (50 $ × 360,50 = 18.025,00), no a la de hoy');
  ok(await pg.evaluate(() => !document.getElementById('ft').value), 'después de cargar, el campo queda vacío para la próxima factura');

  await renglon('Losartán', 'A2', 1); await pg.fill('#fn', '0048214');
  r = await cargar();
  ok(r && r.body.p_factura.numero === '0048214' && !('tasa' in r.body.p_factura), 'sin tasa escrita no se manda ninguna: la base usa la BCV del día de la factura');
  ok(errs.length === 0, 'sin errores de JavaScript' + (errs.length ? ': ' + errs.join(' | ').slice(0, 200) : ''));
  await b.close();
  console.log(fallas ? `\n${fallas} FALLARON` : '\nTodas pasaron'); process.exit(fallas ? 1 : 0);
})();
