// Farmacia: el gráfico «Ventas de los últimos 7 días» del Inicio.
// La escala sale de las ventas reales (no de un tope fijo de $1.500), cada día con ventas lleva su cifra
// y las notas de crédito restan. Supabase simulado.
const { chromium } = require('playwright'); const mock = require('./mock');
(async () => {
  const b = await chromium.launch(); let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
  const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Caracas' }).format(new Date());
  const dia = n => { const d = new Date(hoy + 'T12:00:00'); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };
  let n = 0;
  const doc = (tipo, fecha, bs, afecta) => ({ id: 'doc-' + (++n), empresa_id: 'E', tipo, origen: 'sistema', numero: n, numero_control: null, medio: 'maquina', estado: 'emitido',
    numero_fiscal: n, maquina_registro: 'Z7C0012345', fecha: fecha + 'T15:00:00-04:00', cliente_rif: 'V-00000000', cliente_nombre: 'Consumidor final', tasa: 100,
    total: bs, igtf: 0, ref_tipo: tipo === 'FAC' ? 'venta' : null, afecta_id: afecta || null, motivo: tipo === 'NC' ? 'Devolución' : '', creado_por: 'u-d',
    documento_lineas: [{ renglon: 1, descripcion: 'Losartán 50 mg', cantidad: 1, precio_unit: bs, alicuota: 'E', ref: { producto_id: 1 } }],
    documento_pagos: [{ id: n, metodo: 'Pago móvil', monto_bs: bs }] });
  // Hace 6 días: $6,50 con una nota de crédito de $1,04 → $5,46 neto. Hace 4: $2,73. Hace 1: $20,67 en dos facturas.
  const f1 = doc('FAC', dia(-6), 650);
  const DOCS = [f1, doc('NC', dia(-6), 104, f1.id), doc('FAC', dia(-4), 273), doc('FAC', dia(-1), 1500), doc('FAC', dia(-1), 567)];
  const rest = async (st, { m, p, u, q }) => {
    const uno = (q.headers()['accept'] || '').includes('vnd.pgrst.object');
    if (p === '/rest/v1/productos' && m === 'GET') return { body: [{ id: 1, empresa_id: 'E', codigo: '111', codigos_alt: [], nombre: 'Losartán 50 mg', principio_activo: 'Losartán', iva: 'E', costo: 2, margen: 50, precio: 3, por_lote: false, minimo: 5, rx: false, controlado: false, historial: [] }] };
    if (p === '/rest/v1/documentos' && m === 'GET') return { body: uno ? null : DOCS };
    if (p === '/rest/v1/rpc/tasa_del_dia') return { body: 100 };
    if (p === '/rest/v1/perfiles') return { body: [{ user_id: 'u-d', nombre: 'José Guerrero' }] };
    if (m === 'GET' && p.startsWith('/rest/v1/') && !p.includes('rpc')) return { body: uno ? null : [] };
  };
  const ctx = await b.newContext(); const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message));
  mock(pg, { tasas: [{ fecha: hoy, tasa: 100 }], rest, empresaExtra: { datos_confirmados: true } });
  await pg.goto('http://localhost:8765/farmacia.html'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]');
  await pg.waitForFunction(() => (typeof S === 'object' && S.view !== 'login') && P.length === 1 && FX.docs.length === 5, null, { timeout: 8000 }).catch(() => {});

  const v = await pg.evaluate(() => DAYS.map(d => d.v));
  ok(v.length === 6 && v[0] === 5.46 && v[2] === 2.73 && v[5] === 20.67 && v[1] === 0, 'los seis días anteriores salen de las facturas, con la nota de crédito restada: ' + JSON.stringify(v));

  await pg.evaluate(() => go('dashboard'));
  const svg = await pg.locator('.chart svg').first();
  const textos = await svg.locator('text').allTextContents();
  ok(textos.includes('$30') && !textos.some(t => t.includes('1,5k')), 'la escala se ajusta a la semana ($30), ya no es fija en $1.500');
  ok(['$5,46', '$2,73', '$20,67'].every(t => textos.includes(t)), 'cada día con ventas lleva su cifra');
  ok(textos.filter(t => t === '$0,00').length === 1, 'solo «Hoy» muestra $0,00; los días sin ventas no llevan cifra');
  const alto = await svg.locator('path.bar').nth(5).evaluate(e => e.getBBox().height);
  ok(alto > 100, 'la barra de $20,67 se ve (alto ' + Math.round(alto) + ' de 184)');

  ok(errs.length === 0, 'sin errores de JavaScript ' + errs.join(' | '));
  await b.close(); console.log(fallas ? '\n' + fallas + ' FALLARON' : '\nTodas pasaron'); process.exit(fallas ? 1 : 0);
})();
