// Nómina de la farmacia: que cada botón haga lo que dice (Supabase simulado en memoria)
const { chromium } = require('playwright'); const mock = require('./mock');
(async () => {
  const b = await chromium.launch(); let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
  const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Caracas' }).format(new Date());
  const emp = (id, n, x = {}) => ({ id, n, ci: 'V-27.115.904', cargo: 'Cajero', jor: 'Diurna', est: 'Activo', ing: '2025-03-15', sal: 4409.40, bono: 345, cesta: 40, cargas: 0, ari: null,
    pago: 'Transferencia', banco: 'Banesco', cta: '01340219112190047785', tel: '0424-7351880', hx: 0, hist: [], ...x });
  // Así quedaban los empleados creados antes del arreglo: sin número
  const T = { colecciones: [{ nombre: 'privado_nomina_empleados', datos: [emp(null, 'Kevin Albarrán'), emp(null, 'Mariela Contreras', { pago: 'Pago móvil', banco: 'Mercantil', tel: '0416-6702214', ci: 'V-25.660.218' })] }] };
  const rest = async (st, { m, p, b: body }) => {
    if (p === '/rest/v1/colecciones' && m === 'GET') return { body: T.colecciones };
    if (p === '/rest/v1/colecciones' && m === 'POST') { T.colecciones = T.colecciones.filter(c => c.nombre !== body.nombre).concat([body]); return { body }; }
    if (p === '/rest/v1/rpc/tasa_del_dia') return { body: 100 };
    return { body: [] };
  };
  const ctx = await b.newContext(); await ctx.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: 'http://localhost:8765' });
  const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message));
  mock(pg, { tasas: [{ fecha: hoy, tasa: 100 }], rest, empresaExtra: { rif: 'J-12345678-9', razon_social: 'Azullab Farmacia, C.A.', domicilio: 'Calle 1, La Azulita' } });
  await pg.goto('http://localhost:8765/farmacia.html'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]');
  await pg.waitForFunction(() => typeof S === 'object' && S.view !== 'login' && EMP.length === 2, null, { timeout: 8000 });
  await pg.evaluate(() => { window.__imp = []; window.imprimirDoc = (t, h) => __imp.push({ t, h }); window.__wa = []; window.open = u => { __wa.push(u); return null; }; });
  const app = () => pg.textContent('#app'), modal = () => pg.textContent('#modal');

  ok(await pg.evaluate(() => EMP.map(e => e.id).join() === '1,2'), 'los empleados guardados sin número reciben uno al cargar');
  await pg.evaluate(() => go('employees'));
  ok((await app()).includes('Kevin Albarrán'), 'Empleados abre con la ficha del primero');

  // Nuevo empleado: queda con su número y sin usuario de mentira
  await pg.click('[data-act="empnew"]');
  ok(!(await pg.$('#em-rol')), 'la ficha ya no crea usuarios por su cuenta (se crean en Usuarios)');
  await pg.fill('#em-n', 'Wilmer Rivas'); await pg.fill('#em-ci', 'V-19.442.871'); await pg.fill('#em-cargo', 'Almacén'); await pg.selectOption('#em-pago', 'Efectivo en dólares');
  await pg.click('#empForm [type=submit]'); await pg.waitForTimeout(200);
  ok(await pg.evaluate(() => EMP[2].id === 3 && S.empSel === 3 && EMP[2].hist[0].f === hoyNom()), 'el empleado nuevo queda con el número 3 y la fecha de hoy en su historial');
  await pg.click('body'); await pg.waitForTimeout(500);
  ok(T.colecciones.find(c => c.nombre === 'privado_nomina_empleados').datos.every(e => e.id > 0), 'la nómina se guarda con todos los números');

  // Constancia y AR-I
  await pg.click('[data-act="empsel"][data-id="1"]'); await pg.click('[data-act="empconst"]');
  let m = await modal();
  ok(m.includes('CONSTANCIA DE TRABAJO') && m.includes('Kevin Albarrán') && m.includes('J-12345678-9') && !m.includes('XXXXXXXX'), 'Constancia de trabajo: sale con el empleado y el RIF real de la farmacia');
  await pg.click('[data-act="nomprint"]'); ok(await pg.evaluate(() => __imp.length === 1 && __imp[0].h.includes('CONSTANCIA')), 'Constancia: el botón imprime o guarda en PDF');
  await pg.click('[data-act="close"]'); await pg.click('[data-act="empari"]'); m = await modal();
  ok(m.includes('AR-I') && m.includes('774') && /\d+,\d\d %/.test(m), 'AR-I: muestra el cálculo y el porcentaje de retención');
  await pg.click('[data-act="close"]');

  // Aumento con fecha de hoy entra ya; uno programado vencido entra solo
  await pg.click('[data-act="aumento"]'); await pg.selectOption('#au-que', 'bono'); await pg.selectOption('#au-tipo', 'monto'); await pg.fill('#au-val', '10');
  await pg.click('#aumForm [type=submit]'); await pg.waitForTimeout(200);
  ok(await pg.evaluate(() => EMP[0].bono === 355 && !(EMP[0].prog || []).length), 'Aumento de sueldo con fecha de hoy se aplica de una vez');
  await pg.evaluate(() => { EMP[1].prog = [{ q: 'bono', n: 400, desde: '2026-01-01', txt: 'Bono: $ 345,00 → $ 400,00' }]; go('payroll'); });
  ok(await pg.evaluate(() => EMP[1].bono === 400 && !EMP[1].prog.length), 'un aumento programado entra solo cuando llega su fecha');

  // Pagar: pago móvil, archivo del banco
  await pg.evaluate(() => go('payroll'));
  await pg.click('[data-act="nompagar"]'); m = await modal();
  ok(m.includes('Pagar la quincena') && m.includes('falta la cuenta'), 'Aprobar y pagar abre aunque la farmacia no tenga cuenta cargada, y dice que falta');
  await pg.click('#modal [data-act="nav"]');
  ok(await pg.evaluate(() => S.view === 'config' && document.getElementById('modal').hidden), '«Agregar la cuenta» lleva a Configuración');
  await pg.evaluate(() => { CUENTAS.push({ b: 'Mercantil', t: 'Corriente', n: '0105-0087-51-1087004425', uso: 'Punto de venta' }, { b: 'Banesco', t: 'Corriente', n: '0134-0461-72-4611008712', uso: 'Pago de nómina' }); go('payroll'); });
  await pg.click('[data-act="nompagar"]');
  ok((await modal()).includes('Generar archivo TXT para Banesco'), 'el archivo sale de la cuenta marcada para la nómina');
  await pg.click('[data-act="pmcopy"]'); await pg.waitForTimeout(300);
  const clip = await pg.evaluate(() => navigator.clipboard.readText());
  ok(clip.includes('Mariela Contreras') && clip.includes('0416-6702214') && clip.includes('Mercantil (0105)') && clip.includes('Bs '), 'Copiar datos del pago móvil copia de verdad nombre, banco, teléfono, cédula y monto');
  await pg.click('[data-act="nomtxt"]'); m = await modal();
  ok(await pg.evaluate(() => { const t = txtNomina(); return t.txt.includes('NOMINA ' + QUIN.corto) && t.txt.includes('J123456789') && t.file.includes(QUIN.pago.replace(/\//g, '')); }), 'el archivo del banco lleva la quincena de hoy y el RIF real');
  await pg.click('#modal [data-act="nompagar"]'); await pg.click('[data-act="nomconfirm"]'); await pg.waitForTimeout(200);
  ok((await app()).includes('Pagada el ' + (await pg.evaluate(() => hoyNom().slice(0, 5)))), 'la quincena dice que se pagó hoy, no una fecha fija');

  // Recibos
  ok(await pg.evaluate(() => { const t = reciboText(EMP[0]); return t.includes(UPN(QUIN.nombre)) && t.includes('J-12345678-9') && !t.includes('OCTUBRE 2026 '); }), 'el recibo sale con la quincena de hoy y el RIF real');
  await pg.click('[data-act="recibo"][data-id="1"]'); await pg.click('[data-act="recwa"]'); await pg.waitForTimeout(100);
  ok(await pg.evaluate(() => __wa.length === 1 && __wa[0].startsWith('https://wa.me/584247351880?text=') && decodeURIComponent(__wa[0]).includes('RECIBO DE PAGO')), 'Recibo → WhatsApp abre el chat del empleado con el recibo escrito');
  await pg.click('[data-act="recprint"]'); ok(await pg.evaluate(() => __imp.some(x => x.h.includes('RECIBO DE PAGO'))), 'Recibo → Imprimir');
  await pg.click('#modal [data-act="close"]');
  await pg.click('[data-act="nomrecibos"]'); m = await modal();
  ok(m.includes('1 de 3') && m.includes('Enviado'), 'Enviar recibos abre la lista y marca el que ya se envió');
  await pg.click('#recList [data-act="recwa"][data-id="2"]'); await pg.waitForTimeout(100);
  ok(await pg.evaluate(() => __wa[1].startsWith('https://wa.me/584166702214')), 'cada «Enviar» abre WhatsApp del empleado que es');
  ok(await pg.$('#recList [data-act="recprint"][data-id="3"]') !== null, 'quien no tiene teléfono sale con «Imprimir»');
  await pg.evaluate(() => { marcarRecibo(3); closeModal(); render(); });
  ok((await app()).includes('Recibos enviados'), 'con todos enviados, el paso de recibos queda listo');
  await pg.click('body'); await pg.waitForTimeout(500);
  ok((T.colecciones.find(c => c.nombre === 'privado_nomina_pagos') || { datos: [] }).datos[0].env.length === 3, 'los recibos enviados quedan guardados con el pago');

  // Liquidación: finiquito y egreso
  await pg.evaluate(() => go('employees')); await pg.click('[data-act="empsel"][data-id="2"]'); await pg.click('[data-act="liqde"]');
  await pg.click('[data-act="finiq"]'); m = await modal();
  ok(m.includes('FINIQUITO') && m.includes('Mariela Contreras') && m.includes('Total a pagar'), 'Finiquito en PDF: sale con los conceptos y el total');
  await pg.click('[data-act="close"]'); await pg.click('[data-act="egreso"]');
  ok(await pg.evaluate(() => EMP[1].est === 'Egresado' && EMP[1].egreso === QUIN.hoyIso), 'Registrar egreso guarda la fecha de egreso');
  await pg.evaluate(() => go('employees')); await pg.click('[data-act="empsel"][data-id="2"]'); await pg.click('[data-act="empconst"]');
  ok((await modal()).includes('prestó sus servicios'), 'la constancia de quien egresó dice hasta cuándo trabajó');

  ok(errs.length === 0, 'sin errores de JavaScript ' + errs.join(' | '));
  await b.close(); process.exit(fallas ? 1 : 0);
})();
