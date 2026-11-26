package main

import (
	"encoding/json"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

type Servidor struct {
	cfg   *Config
	im    *Impresora
	salir func(codigo int)
}

func (s *Servidor) rutas() http.Handler {
	m := http.NewServeMux()
	m.HandleFunc("/estado", s.soloGET(func(w http.ResponseWriter, r *http.Request) { s.json(w, s.im.Estado()) }))
	m.HandleFunc("/documento", s.soloPOST(func(w http.ResponseWriter, r *http.Request) {
		var d Documento
		if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&d); err != nil {
			s.json(w, Respuesta{"ok": false, "error": "La factura llegó mal armada: " + err.Error()})
			return
		}
		s.json(w, s.im.Documento(d))
	}))
	m.HandleFunc("/reporte-x", s.soloPOST(func(w http.ResponseWriter, r *http.Request) { s.json(w, s.im.Reporte(false)) }))
	m.HandleFunc("/reporte-z", s.soloPOST(func(w http.ResponseWriter, r *http.Request) { s.json(w, s.im.Reporte(true)) }))
	// Herramientas de la página del agente (solo desde esta misma computadora, sin Origin de afuera)
	m.HandleFunc("/programacion", s.soloLocal(func(w http.ResponseWriter, r *http.Request) { s.json(w, s.im.ImprimirProgramacion()) }))
	m.HandleFunc("/medios", s.soloLocal(func(w http.ResponseWriter, r *http.Request) { s.json(w, s.im.ProgramarMedios()) }))
	m.HandleFunc("/diagnostico", func(w http.ResponseWriter, r *http.Request) {
		if !s.local(r) {
			http.Error(w, "solo desde la página del agente", http.StatusForbidden)
			return
		}
		t := s.im.Diagnostico()
		_ = os.WriteFile(rutaDatos("diagnostico.txt"), []byte(t), 0o644)
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		_, _ = io.WriteString(w, t)
	})
	m.HandleFunc("/apagar", s.soloLocal(func(w http.ResponseWriter, r *http.Request) {
		s.json(w, Respuesta{"ok": true})
		go func() { time.Sleep(300 * time.Millisecond); s.salir(codigoApagar) }()
	}))
	m.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = io.WriteString(w, strings.ReplaceAll(pagina, "{{version}}", version))
	})
	return s.envolver(m)
}

// envolver aplica las reglas de seguridad y CORS a todas las rutas.
func (s *Servidor) envolver(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Contra «DNS rebinding»: solo se atiende a 127.0.0.1 o localhost.
		host, _, err := net.SplitHostPort(r.Host)
		if err != nil {
			host = r.Host
		}
		if host != "127.0.0.1" && host != "localhost" {
			http.Error(w, "host no permitido", http.StatusForbidden)
			return
		}
		o := r.Header.Get("Origin")
		if !s.cfg.origenPermitido(o) {
			http.Error(w, "origen no permitido", http.StatusForbidden)
			return
		}
		if o != "" {
			w.Header().Set("Access-Control-Allow-Origin", o)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Headers", "content-type")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST")
			w.Header().Set("Access-Control-Allow-Private-Network", "true")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		h.ServeHTTP(w, r)
	})
}

func (s *Servidor) local(r *http.Request) bool {
	o := r.Header.Get("Origin")
	return o == "" || strings.HasPrefix(o, "http://127.0.0.1:") || strings.HasPrefix(o, "http://localhost:")
}

func (s *Servidor) soloGET(f http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "usa GET", http.StatusMethodNotAllowed)
			return
		}
		f(w, r)
	}
}

func (s *Servidor) soloPOST(f http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "usa POST", http.StatusMethodNotAllowed)
			return
		}
		f(w, r)
	}
}

func (s *Servidor) soloLocal(f http.HandlerFunc) http.HandlerFunc {
	return s.soloPOST(func(w http.ResponseWriter, r *http.Request) {
		if !s.local(r) {
			http.Error(w, "solo desde la página del agente", http.StatusForbidden)
			return
		}
		f(w, r)
	})
}

func (s *Servidor) json(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(v)
}

const pagina = `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Agente Cuadre · impresora fiscal</title>
<style>
body{font:16px/1.5 system-ui,Segoe UI,sans-serif;background:#0f1d3a;color:#1d2433;margin:0;padding:24px}
main{max-width:640px;margin:0 auto;background:#fbf8f1;border-radius:14px;padding:24px 28px;box-shadow:0 8px 30px #0006}
h1{font-size:22px;margin:0 0 4px}.sub{color:#667;margin:0 0 18px;font-size:14px}
.est{padding:12px 14px;border-radius:10px;background:#eef2ff;margin:12px 0;white-space:pre-wrap}
.ok{background:#e5f6ec;color:#14532d}.mal{background:#fdecec;color:#7f1d1d}
button{font:inherit;padding:10px 14px;border-radius:9px;border:1px solid #c9c3b4;background:#fff;cursor:pointer;margin:4px 6px 4px 0}
button.p{background:#1f7a4a;color:#fff;border-color:#1f7a4a}pre{background:#fff;border:1px dashed #c9c3b4;padding:10px;font-size:12px;overflow:auto;max-height:320px}
small{color:#667}
</style></head><body><main>
<h1>Agente Cuadre · impresora fiscal</h1><p class="sub">Versión {{version}} · conecta la caja de Cuadre con la impresora de esta computadora.</p>
<div id="est" class="est">Revisando la impresora…</div>
<button class="p" onclick="estado()">Revisar de nuevo</button>
<button onclick="post('/programacion','Imprimiendo la programación (tasas, medios de pago y flags)…')">Imprimir programación</button>
<button onclick="if(confirm('¿Grabar en la impresora los nombres de los medios de pago 01 a 06?'))post('/medios','Programando medios de pago…')">Programar medios de pago</button>
<button onclick="diag()">Diagnóstico</button>
<pre id="out" hidden></pre>
<p><small>En Cuadre (farmacia, como dueño): Módulo fiscal → Configurar la impresora → agente <b>http://127.0.0.1:7123</b>.
Si el diagnóstico muestra errores, cópialo y mándaselo a Cuadre.</small></p>
<script>
const $=id=>document.getElementById(id);
function pinta(j){const e=$('est');e.className='est '+(j.ok?'ok':'mal');
 e.textContent=j.ok?('Impresora lista: '+(j.modelo||'')+' · registro '+(j.registro||'—')+' · RIF '+(j.rif||'—')+'\nFlags '+(j.flags||'')+(j.memoria?' · memoria '+j.memoria:'')+(j.aviso?'\n'+j.aviso:'')):('No está lista: '+j.error)}
async function estado(){$('est').textContent='Revisando la impresora…';try{pinta(await (await fetch('/estado')).json())}catch(x){pinta({ok:false,error:String(x)})}}
async function post(u,t){$('est').className='est';$('est').textContent=t;try{const j=await (await fetch(u,{method:'POST'})).json();
 if(j.ok){$('est').className='est ok';$('est').textContent='Listo'+(j.hechos?': '+j.hechos.join(', '):'')}else pinta(j)}catch(x){pinta({ok:false,error:String(x)})}}
async function diag(){const o=$('out');o.hidden=false;o.textContent='Leyendo la impresora…';try{o.textContent=await (await fetch('/diagnostico')).text()}catch(x){o.textContent=String(x)}}
estado();
</script></main></body></html>`
