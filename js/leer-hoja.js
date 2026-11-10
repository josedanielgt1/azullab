/* =====================================================================
   Cuadre · Leer una hoja de cálculo en el navegador (sin librerías)
     * .xlsx: es un ZIP con XML adentro. Se lee la primera hoja.
     * .csv / .txt: separado por punto y coma, coma o tabulador.
   Devuelve las filas como listas de celdas: los números de Excel llegan
   como número; todo lo demás, como texto. Quien las usa decide qué es
   una fecha o un precio.
       const filas = await Cuadre.leerHoja(archivo)
   ===================================================================== */
(() => {
  const C = window.Cuadre = window.Cuadre || {};

  /* ---------------- ZIP ---------------- */
  async function inflar(bytes) {
    if (typeof DecompressionStream !== 'function') throw new Error('Este navegador no abre archivos de Excel: guarda la hoja como CSV y súbela así');
    const s = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('deflate-raw'));
    return new Uint8Array(await new Response(s).arrayBuffer());
  }
  function indiceZip(buf) {
    const dv = new DataView(buf), n = buf.byteLength;
    let fin = -1;
    for (let i = n - 22; i >= Math.max(0, n - 66000); i--) if (dv.getUint32(i, true) === 0x06054b50) { fin = i; break; }
    if (fin < 0) throw new Error('El archivo no es un Excel (.xlsx) válido');
    const total = dv.getUint16(fin + 10, true); let p = dv.getUint32(fin + 16, true);
    const td = new TextDecoder(), out = {};
    for (let k = 0; k < total; k++) {
      if (p + 46 > n || dv.getUint32(p, true) !== 0x02014b50) break;
      const metodo = dv.getUint16(p + 10, true), comp = dv.getUint32(p + 20, true), largo = dv.getUint16(p + 28, true),
        extra = dv.getUint16(p + 30, true), coment = dv.getUint16(p + 32, true), local = dv.getUint32(p + 42, true);
      out[td.decode(new Uint8Array(buf, p + 46, largo))] = {metodo, comp, local};
      p += 46 + largo + extra + coment;
    }
    return out;
  }
  async function archivoZip(buf, idx, nombre) {
    const e = idx[nombre]; if (!e) return null;
    const dv = new DataView(buf);
    if (dv.getUint32(e.local, true) !== 0x04034b50) throw new Error('El archivo de Excel está dañado');
    const ini = e.local + 30 + dv.getUint16(e.local + 26, true) + dv.getUint16(e.local + 28, true);
    const datos = new Uint8Array(buf, ini, e.comp);
    if (e.metodo === 0) return new TextDecoder().decode(datos);
    if (e.metodo !== 8) throw new Error('El archivo de Excel usa una compresión que no se reconoce: guárdalo de nuevo como .xlsx');
    return new TextDecoder().decode(await inflar(datos));
  }

  /* ---------------- XLSX ---------------- */
  const xml = t => new DOMParser().parseFromString(t, 'application/xml');
  const hijos = (n, nombre) => [...n.childNodes].filter(x => x.localName === nombre);
  const textoDe = n => [...n.getElementsByTagNameNS('*', 't')].filter(t => t.parentNode.localName !== 'rPh').map(t => t.textContent).join('');
  const columna = ref => { let c = 0; for (const ch of String(ref || '').replace(/\d+/g, '')) c = c * 26 + (ch.charCodeAt(0) - 64); return c - 1; };

  async function leerXlsx(buf) {
    const idx = indiceZip(buf);
    // La primera hoja del libro, según el orden que el libro declara
    let ruta = 'xl/worksheets/sheet1.xml';
    const libro = await archivoZip(buf, idx, 'xl/workbook.xml'), rels = await archivoZip(buf, idx, 'xl/_rels/workbook.xml.rels');
    if (libro && rels) {
      const hoja = xml(libro).getElementsByTagNameNS('*', 'sheet')[0];
      const rid = hoja && [...hoja.attributes].find(a => a.localName === 'id');
      const rel = rid && [...xml(rels).getElementsByTagNameNS('*', 'Relationship')].find(r => r.getAttribute('Id') === rid.value);
      if (rel) { const t = rel.getAttribute('Target'); ruta = t.startsWith('/') ? t.slice(1) : 'xl/' + t.replace(/^\.\//, ''); }
    }
    const hojaXml = await archivoZip(buf, idx, ruta);
    if (!hojaXml) throw new Error('No se encontró ninguna hoja en el archivo de Excel');
    const ss = await archivoZip(buf, idx, 'xl/sharedStrings.xml');
    const textos = ss ? [...xml(ss).getElementsByTagNameNS('*', 'si')].map(textoDe) : [];
    const filas = [];
    for (const row of xml(hojaXml).getElementsByTagNameNS('*', 'row')) {
      const f = []; let sig = 0;
      for (const c of hijos(row, 'c')) {
        const i = c.hasAttribute('r') ? columna(c.getAttribute('r')) : sig; sig = i + 1;
        const t = c.getAttribute('t'), v = hijos(c, 'v')[0];
        let val = '';
        if (t === 'inlineStr') val = textoDe(c);
        else if (!v) val = '';
        else if (t === 's') val = textos[+v.textContent] ?? '';
        else if (t === 'str' || t === 'e') val = t === 'e' ? '' : v.textContent;
        else if (t === 'b') val = v.textContent === '1' ? 'Sí' : 'No';
        else { const x = Number(v.textContent); val = Number.isFinite(x) ? x : v.textContent; }
        f[i] = typeof val === 'string' ? val.trim() : val;
      }
      const num = +row.getAttribute('r'); const pos = num > 0 ? num - 1 : filas.length;
      while (filas.length < pos && filas.length < 20000) filas.push([]);
      filas.push(Array.from(f, x => x ?? ''));
    }
    return filas;
  }

  /* ---------------- CSV ---------------- */
  function leerCsv(texto) {
    texto = texto.replace(/^﻿/, '');
    const primera = texto.split(/\r?\n/).find(l => l.trim()) || '';
    const cuenta = s => { let n = 0, q = false; for (const ch of primera) { if (ch === '"') q = !q; else if (ch === s && !q) n++; } return n; };
    const sep = [';', '\t', ','].map(s => [s, cuenta(s)]).sort((a, b) => b[1] - a[1])[0][0];
    const filas = []; let f = [], c = '', q = false;
    for (let i = 0; i < texto.length; i++) {
      const ch = texto[i];
      if (q) { if (ch === '"') { if (texto[i + 1] === '"') { c += '"'; i++; } else q = false; } else c += ch; }
      else if (ch === '"' && c === '') q = true;
      else if (ch === sep) { f.push(c.trim()); c = ''; }
      else if (ch === '\n' || ch === '\r') { if (ch === '\r' && texto[i + 1] === '\n') i++; f.push(c.trim()); filas.push(f); f = []; c = ''; }
      else c += ch;
    }
    if (c !== '' || f.length) { f.push(c.trim()); filas.push(f); }
    return filas;
  }

  C.leerHoja = async archivo => {
    const buf = await archivo.arrayBuffer();
    if (!buf.byteLength) throw new Error('El archivo está vacío');
    if (buf.byteLength > 15 * 1024 * 1024) throw new Error('El archivo pasa de 15 MB: deja solo la hoja de productos');
    const b = new Uint8Array(buf, 0, Math.min(8, buf.byteLength));
    let filas;
    if (b[0] === 0x50 && b[1] === 0x4b) filas = await leerXlsx(buf);
    else if (b[0] === 0xd0 && b[1] === 0xcf) throw new Error('Ese es un Excel viejo (.xls). Ábrelo y guárdalo como «Libro de Excel (.xlsx)» o como CSV');
    else {
      let t = new TextDecoder('utf-8').decode(buf);
      if (t.includes('�')) t = new TextDecoder('windows-1252').decode(buf);   // CSV guardado por Excel en Windows
      filas = leerCsv(t);
    }
    // Sin las filas ni las columnas vacías del final
    filas = filas.map(f => { const g = f.slice(); while (g.length && (g[g.length - 1] === '' || g[g.length - 1] == null)) g.pop(); return g; });
    while (filas.length && !filas[filas.length - 1].length) filas.pop();
    return filas;
  };
})();
