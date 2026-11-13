// Ningún texto de la maqueta a la vista: recorre todas las pantallas de los tres sistemas con cada rol
const { chromium } = require('playwright'); const mock = require('./mock');
const MAQUETA = /\(muestra\)|de muestra|muestra\)|demostraci|maqueta|propuesta|ningún dato es real|ninguno es real|de ejemplo|Uzcátegui|Albarrán|Rosángela|Wilmer|Mariela|Yusmely|Albornoz|Yorbelis|Rondón|Zambrano/i;
// La farmacia factura solo por máquina fiscal: ni imprenta digital ni talonario de contingencia a la vista
const SOLO_MAQUINA = /imprenta|talonario|contingencia/i;
const ROLES = { farmacia: ['dueno', 'gerente', 'regente', 'cajero', 'almacen'], laboratorio: ['dueno', 'bioanalista', 'atencion', 'toma_muestras'], crossfit: ['dueno', 'coach', 'socio'] };
(async () => {
  const b = await chromium.launch(); let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
  const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Caracas' }).format(new Date());
  for (const sys of Object.keys(ROLES)) for (const rol of ROLES[sys]) {
    const ctx = await b.newContext(); const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message));
    mock(pg, { tipo: sys, rol, tasas: [{ fecha: hoy, tasa: 100 }], empresaExtra: sys === 'farmacia' ? {} : { talonario_desde: 1, talonario_hasta: 50 } });
    await pg.goto(`http://localhost:8765/${sys}.html`); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]');
    await pg.waitForFunction(() => (typeof S === 'object' && S.view !== 'login'), null, { timeout: 8000 }); await pg.waitForTimeout(500);
    const vistas = await pg.evaluate(() => NAV.flatMap(g => g.items.map(i => i[1])));
    const hallados = [], imprenta = [];
    const mirar = async donde => { const t = await pg.evaluate(() => (document.querySelector('main') || document.body).innerText);
      t.split('\n').filter(l => MAQUETA.test(l.replace(/toma de muestras?/gi, ''))).forEach(l => hallados.push(`${donde}: ${l.trim().slice(0, 160)}`));
      if (sys === 'farmacia') t.split('\n').filter(l => SOLO_MAQUINA.test(l)).forEach(l => imprenta.push(`${donde}: ${l.trim().slice(0, 160)}`)); };
    await mirar('inicio');
    for (const v of vistas) {
      await pg.evaluate(x => go(x), v).catch(() => {});
      await mirar(v);
      const n = (await pg.$$('[data-act="fx-tab"],[data-act="tab"]')).length;
      for (let i = 0; i < n; i++) { const bs = await pg.$$('[data-act="fx-tab"],[data-act="tab"]'); if (!bs[i]) break; await bs[i].click().catch(() => {}); await mirar(v + '/' + i); }
    }
    const unicos = [...new Set(hallados)]; unicos.forEach(l => console.log('   ' + l));
    ok(unicos.length === 0, `${sys} · ${rol}: ningún texto de maqueta en ${vistas.length} pantallas`);
    if (sys === 'farmacia') { const u = [...new Set(imprenta)]; u.forEach(l => console.log('   ' + l)); ok(u.length === 0, `farmacia · ${rol}: nada de imprenta ni talonario en ${vistas.length} pantallas`); }
    if (rol === 'dueno') {
      ok(await pg.evaluate(() => FX.docs.length) === 0, `${sys}: sin facturas de la maqueta`);
      await pg.evaluate(() => go('checklist')); ok((await pg.textContent('main')).includes('sin monto a pagar'), `${sys}: negocio nuevo, la declaración no inventa un monto a pagar`);
    }
    await ctx.close();
  }
  await b.close(); process.exit(fallas ? 1 : 0);
})();
