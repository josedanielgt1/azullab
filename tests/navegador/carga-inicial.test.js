// Carga inicial del inventario: hoja de Excel o CSV, a mano, y cierre (Supabase simulado en memoria)
const { chromium } = require('playwright'); const mock = require('./mock'); const path = require('path');
(async () => {
  const b = await chromium.launch(); let fallas = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FALLA ') + m); if (!c) fallas++; };
  const aqui = f => path.join(__dirname, f);
  const nuevo = async (rol, extra) => {
    const T = { productos: [], lotes: [], rpc: [], seq: 1 };
    const rest = async (st, { m, p, u, b: body }) => {
      if (p === '/rest/v1/productos' && m === 'GET') return { body: T.productos };
      if (p === '/rest/v1/productos' && m === 'POST') { const r = { activo: true, codigos_alt: [], ...body, id: T.seq++ }; T.productos.push(r); return { body: r }; }
      if (p === '/rest/v1/lotes' && m === 'GET') return { body: T.lotes };
      if (p === '/rest/v1/perfiles') return { body: [{ user_id: 'u-d', nombre: 'José Guerrero' }] };
      if (p === '/rest/v1/rpc/tasa_del_dia') return { body: 100 };
      if (p.startsWith('/rest/v1/rpc/')) T.rpc.push({ f: p.slice(13), body });
      if (p === '/rest/v1/rpc/carga_inicial') {
        if (T.falla) return { status: 400, body: { message: T.falla } };
        let nuevos = 0, lotes = 0, unidades = 0;
        for (const it of body.p_items) {
          let pr = it.producto_id ? T.productos.find(x => x.id === it.producto_id) : it.codigo ? T.productos.find(x => x.codigo === it.codigo) : T.productos.find(x => x.nombre.toLowerCase() === it.nombre.toLowerCase());
          if (!pr) { pr = { id: T.seq++, activo: true, codigo: it.codigo || null, codigos_alt: it.codigos_alt || [], nombre: it.nombre, principio_activo: it.principio_activo || null, laboratorio: it.laboratorio || null, presentacion: it.presentacion || null, seccion: it.seccion || null, iva: it.iva || 'E', costo: it.costo || 0, margen: it.margen ?? 30, precio: it.precio ?? Math.round((it.costo || 0) * (1 + (it.margen ?? 30) / 100) * 100) / 100, pmvp: null, por_lote: false, minimo: 5, rx: !!it.rx, controlado: !!it.controlado, historial: [] }; T.productos.push(pr); nuevos++; }
          if (it.cantidad > 0) { const lote = (it.lote || 'S/L').toUpperCase(); let l = T.lotes.find(x => x.producto_id === pr.id && x.lote === lote && x.vence === it.vence);
            if (l) l.cantidad += it.cantidad; else T.lotes.push({ id: T.seq++, empresa_id: 'E', producto_id: pr.id, lote, vence: it.vence, cantidad: it.cantidad, costo: it.costo ?? pr.costo, precio: null });
            lotes++; unidades += it.cantidad; }
        }
        return { body: { renglones: body.p_items.length, productos_nuevos: nuevos, lotes, unidades } };
      }
      if (p === '/rest/v1/rpc/cerrar_carga_inicial') return { body: '2026-11-21T12:00:00+00:00' };
      if (p.startsWith('/rest/v1/rpc/')) return { body: [] };
      if (m === 'GET') return { body: [] };
    };
    const ctx = await b.newContext(); const pg = await ctx.newPage(); const errs = []; pg.on('pageerror', e => errs.push(e.message));
    mock(pg, { rol, tasas: [{ fecha: new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Caracas' }).format(new Date()), tasa: 100 }], rest, empresaExtra: extra || {} });
    await pg.goto('http://localhost:8765/farmacia.html'); await pg.fill('#lu', 'jose@azullab.com'); await pg.fill('#lp', 'clave-buena'); await pg.click('#loginForm [type=submit]');
    await pg.waitForFunction(() => (typeof S === 'object' && S.view !== 'login'), null, { timeout: 8000 });
    await pg.evaluate(() => go('purchases'));
    return { T, pg, errs, ctx };
  };
  const txt = pg => pg.evaluate(() => { const c = document.querySelector('.content').cloneNode(true); c.querySelectorAll('select').forEach(x => x.remove()); return c.textContent.replace(/\s+/g, ' '); });
  const espera = (pg, re) => pg.waitForFunction(r => new RegExp(r).test(document.getElementById('toast').textContent), re, { timeout: 8000 }).catch(() => {});
  const aviso = pg => pg.textContent('#toast');

  let { T, pg, errs, ctx } = await nuevo('dueno');
  ok(!(await txt(pg)).includes('Importar archivo') && !(await txt(pg)).includes('Guardar borrador'), 'Compras ya no muestra los botones de maqueta (Importar archivo, Guardar borrador)');
  await pg.click('[data-act="buytab"][data-k="initial"]');
  let t = await txt(pg);
  ok(t.includes('no va al Libro de Compras') && !t.includes('1.240'), 'la pestaña explica que no es una compra y no trae cifras de muestra');
  ok(await pg.evaluate(() => fetch('assets/plantilla-carga-inicial.xlsx').then(r => r.ok && +r.headers.get('content-length') > 3000)), 'la plantilla se descarga');

  // Hoja exportada de otro sistema: título arriba, encabezados distintos, filas malas
  await pg.setInputFiles('#ini-file', aqui('hoja-otro-sistema.xlsx')); await pg.waitForSelector('[data-inimap="nombre"]');
  const mapa = () => pg.evaluate(() => Object.fromEntries([...document.querySelectorAll('[data-inimap]')].map(s => [s.dataset.inimap, +s.value])));
  let m = await mapa();
  ok((await txt(pg)).includes('encabezados en la fila 3'), 'encuentra la fila de encabezados aunque haya un título arriba');
  ok(m.codigo === 0 && m.nombre === 1 && m.laboratorio === 2 && m.costo === 3 && m.precio === 4 && m.cantidad === 5 && m.vence === 6 && m.lote === 7, 'reconoce las columnas de otro sistema (COD, DESCRIPCION, MARCA, PVP, EXISTENCIA…)');
  ok(m.margen === -1 && m.iva === -1, 'lo que la hoja no trae queda en «No viene»');
  t = await txt(pg);
  ok(t.includes('Fila 6: el nombre no puede llevar') && t.includes('Fila 7: trae cantidad pero no la fecha de vencimiento') && t.includes('Fila 8: el costo no es un número válido'), 'dice qué fila está mal y por qué');
  ok(await pg.evaluate(() => !document.querySelector('.content td b b') && !document.querySelector('.content li b')), 'lo que viene en la hoja se muestra como texto, nunca como HTML');
  ok(await pg.isDisabled('[data-act="ini-subir"]'), 'con errores no deja cargar');
  await pg.check('#ini-sinv'); t = await txt(pg);
  ok(!t.includes('Fila 7') && t.includes('1 solo al catálogo'), 'con «no trae vencimientos», esa fila entra solo al catálogo');
  ok(T.rpc.every(r => r.f !== 'carga_inicial'), 'hasta aquí no se guardó nada');
  await pg.click('[data-act="ini-quitar"]');
  ok(await pg.isVisible('#ini-file', { strict: false }).catch(() => false) || await pg.evaluate(() => !!document.getElementById('ini-file')), 'se puede quitar el archivo y escoger otro');

  // La plantilla de Cuadre llena
  await pg.setInputFiles('#ini-file', aqui('plantilla-llena.xlsx')); await pg.waitForSelector('[data-inimap="nombre"]');
  m = await mapa();
  ok(Object.values(m).every(v => v >= 0) && Object.keys(m).length === 18, 'la plantilla de Cuadre: se reconocen sus 18 columnas');
  t = await txt(pg);
  ok(t.includes('5 renglones') && t.includes('4 productos nuevos') && t.includes('5 con existencia · 51 unidades') && !t.includes('con error'), 'resume la hoja: 5 renglones, 4 productos nuevos, 51 unidades');
  await pg.click('[data-act="ini-subir"]'); await pg.waitForFunction(() => P.length === 4, null, { timeout: 8000 }).catch(() => {});
  let c = T.rpc.find(r => r.f === 'carga_inicial');
  ok(c && c.body.p_items.length === 5 && c.body.p_empresa === 'E', 'cargar llama a carga_inicial() con los 5 renglones');
  const it0 = c.body.p_items[0], it2 = c.body.p_items[2], it4 = c.body.p_items[4];
  ok(it0.codigo === '7591020311042' && it0.nombre === 'Losartán potásico 50 mg' && it0.lote === 'GV24L118' && it0.vence === '2027-01-31' && it0.cantidad === 5 && it0.costo === 2.1 && it0.margen === 30 && it0.iva === 'E', 'cada renglón va con código, lote, vencimiento (fecha de Excel), cantidad, costo y ganancia');
  ok(it0.codigos_alt && it0.codigos_alt[0] === '7591020311059', 'con sus códigos alternos');
  ok(it2.vence === '2027-06-30', 'un vencimiento como «06/2027» es el último día de ese mes');
  ok(it4.controlado === true && it4.rx === true, 'los controlados van marcados');
  ok(!('_n' in it0) && !('_nom' in it0), 'sin datos internos de la pantalla');
  ok(await pg.evaluate(() => P.length === 4 && P.find(p => p.code === '7591020311042').stock === 15), 'el catálogo se recarga de la base: Losartán con 15 en dos lotes');
  ok(T.rpc.every(r => !/recibir_/.test(r.f)), 'no pasa por recibir_factura: no hay factura ni Libro de Compras');
  ok(await pg.evaluate(() => COMPRAS_LIBRO.length === 0), 'el Libro de Compras sigue vacío');
  await espera(pg, 'Carga inicial lista');
  ok(/Carga inicial lista: 4 productos nuevos y 51 unidades/.test(await aviso(pg)), 'avisa lo que entró');

  // La misma hoja otra vez: avisa que se sumaría
  await pg.setInputFiles('#ini-file', aqui('plantilla-llena.xlsx')); await pg.waitForSelector('[data-inimap="nombre"]');
  t = await txt(pg);
  ok(t.includes('ya están cargados') && t.includes('0 productos nuevos'), 'si la hoja ya se subió, avisa que los lotes ya están cargados');
  await pg.click('[data-act="ini-quitar"]');

  // CSV de Excel en Windows: punto y coma, coma decimal y acentos en windows-1252
  const csv = Buffer.from('Código;Nombre;Costo;Precio;Cantidad;Vencimiento;Lote;IVA\r\n7591020300053;"Jarabe para la tos; niños";1,50;2,25;1.200;31/12/2027;jt01;16%\r\n', 'latin1');
  await pg.setInputFiles('#ini-file', { name: 'inventario.csv', mimeType: 'text/csv', buffer: csv }); await pg.waitForSelector('[data-inimap="nombre"]');
  T.rpc.length = 0; await pg.click('[data-act="ini-subir"]'); await pg.waitForFunction(() => P.length === 5, null, { timeout: 8000 }).catch(() => {});
  await espera(pg, '1 productos nuevos');
  c = (T.rpc.find(r => r.f === 'carga_inicial') || { body: { p_items: [{}] } }).body.p_items[0];
  ok(c.nombre === 'Jarabe para la tos; niños' && c.costo === 1.5 && c.precio === 2.25 && c.cantidad === 1200 && c.vence === '2027-12-31' && c.lote === 'JT01' && c.iva === 'G', 'CSV: separador, comillas, acentos, coma decimal, miles con punto y fecha día/mes/año');
  ok(c.margen === 50, 'si trae costo y precio pero no ganancia, la ganancia sale de ahí (50 %)');

  // A mano
  await pg.fill('#iniscan', '0000000'); await pg.press('#iniscan', 'Enter');
  ok(/No está en el catálogo/.test(await aviso(pg)), 'a mano: un producto que no está en el catálogo no se agrega');
  await pg.fill('#iniscan', 'acetamin'); await pg.press('#iniscan', 'Enter'); await pg.waitForSelector('[data-ini="0"]');
  await pg.click('[data-act="ini-cargar"]');
  ok(/Completa vencimiento y cantidad en 1 renglón/.test(await aviso(pg)), 'sin vencimiento ni cantidad no carga');
  await pg.fill('[data-ini="0"][data-f="l"]', 'cx12'); await pg.fill('[data-ini="0"][data-f="e"]', '2028-01-31'); await pg.fill('[data-ini="0"][data-f="q"]', '7'); await pg.fill('[data-ini="0"][data-f="c"]', '0,85'); await pg.press('[data-ini="0"][data-f="c"]', 'Tab');
  T.rpc.length = 0; T.falla = 'Renglón 1: falta la fecha de vencimiento'; await pg.click('[data-act="ini-cargar"]'); await pg.waitForTimeout(600);
  ok(/Renglón 1/.test(await aviso(pg)) && await pg.evaluate(() => !!document.querySelector('[data-ini="0"]')), 'si la base rechaza la carga, muestra el motivo y el renglón sigue en pantalla');
  T.falla = null; T.rpc.length = 0; await pg.click('[data-act="ini-cargar"]');
  await pg.waitForFunction(() => { const p = P.find(x => x.name.startsWith('Acetamin')); return p && p.stock === 27; }, null, { timeout: 8000 }).catch(() => {});
  c = T.rpc.find(r => r.f === 'carga_inicial');
  const ac = T.productos.find(x => x.nombre.startsWith('Acetamin'));
  ok(c && JSON.stringify(c.body.p_items) === JSON.stringify([{ producto_id: ac.id, lote: 'CX12', vence: '2028-01-31', cantidad: 7, costo: 0.85 }]), 'a mano: el renglón va con el producto del catálogo, lote, vencimiento, cantidad y costo');
  await espera(pg, '0 productos nuevos y 7 unidades'); await pg.waitForFunction(() => !document.querySelector('[data-ini]'), null, { timeout: 5000 }).catch(() => {});
  ok(await pg.evaluate(() => P.find(x => x.name.startsWith('Acetamin')).stock === 27 && !document.querySelector('[data-ini]')), 'la existencia sube (20 + 7) y la lista queda limpia');

  // Cerrar
  await pg.click('[data-act="ini-cerrar"]');
  ok((await pg.textContent('#modal')).includes('no se puede volver a abrir'), 'cerrar avisa que no se vuelve a abrir');
  await pg.click('[data-act="ini-cerrar-ok"]'); await pg.waitForFunction(() => document.querySelector('.content').textContent.includes('se cerró el'), null, { timeout: 5000 }).catch(() => {});
  t = await txt(pg);
  ok(T.rpc.some(r => r.f === 'cerrar_carga_inicial') && t.includes('se cerró el 21/11/2026') && !(await pg.evaluate(() => !!document.getElementById('iniscan'))), 'cerrada: queda la fecha y ya no se puede cargar');
  ok(errs.length === 0, 'sin errores de JavaScript' + (errs.length ? ': ' + errs.join(' | ').slice(0, 200) : ''));
  await ctx.close();

  // Quien no es dueño ni gerente
  ({ T, pg, errs, ctx } = await nuevo('almacen'));
  await pg.click('[data-act="buytab"][data-k="initial"]');
  ok((await txt(pg)).includes('la hace el dueño o el gerente') && !(await pg.evaluate(() => !!document.getElementById('ini-file'))), 'almacén ve la pestaña pero no puede hacer la carga inicial');
  await ctx.close();
  ({ T, pg, errs, ctx } = await nuevo('gerente'));
  await pg.click('[data-act="buytab"][data-k="initial"]');
  ok(await pg.evaluate(() => !!document.getElementById('ini-file') && !document.querySelector('[data-act="ini-cerrar"]')), 'el gerente carga, pero solo el dueño cierra');
  await ctx.close();
  ({ T, pg, errs, ctx } = await nuevo('dueno', { carga_inicial_cerrada: '2026-11-21T12:00:00+00:00' }));
  await pg.click('[data-act="buytab"][data-k="initial"]');
  ok((await txt(pg)).includes('se cerró el 21/11/2026'), 'al volver a entrar, la carga cerrada sigue cerrada');
  await ctx.close();

  await b.close();
  console.log(fallas ? `\n${fallas} FALLARON` : '\nTodas pasaron'); process.exit(fallas ? 1 : 0);
})();
