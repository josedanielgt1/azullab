package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func preparar(t *testing.T) (*Impresora, *Simulador) {
	t.Helper()
	sim := nuevoSimulador()
	cfg := configPorDefecto()
	reg := abrirRegistro(filepath.Join(t.TempDir(), "impresos.json"))
	im := nuevaImpresora(cfg, func() (Puerto, error) { return sim, nil }, reg, func(s string) { t.Log(s) })
	im.pausa = func(time.Duration) {}
	return im, sim
}

func ptr[T any](v T) *T { return &v }

func factura(id string) Documento {
	return Documento{ID: id, Tipo: "FAC", Fecha: "2026-11-26T10:00:00-04:00",
		Cliente: Cliente{RIF: "V-00000000", Nombre: "Consumidor final"},
		Lineas: []Linea{
			{Descripcion: "Losartán 50 mg · Caja x 30", Cantidad: 2, Precio: 300, Alicuota: "E"},
			{Descripcion: "Champú", Cantidad: 1, Precio: 100, Alicuota: "G"},
		},
		Pagos:   []Pago{{Metodo: "Pago móvil", Monto: 500}, {Metodo: "Efectivo USD", Monto: 300}},
		Totales: Totales{Exento: 600, BaseGeneral: 100, IvaGeneral: 16, Total: 716},
		Pie:     []string{"REF. USD 7,16", "TASA BCV 100,00"}}
}

func TestTramaLRC(t *testing.T) {
	// Ejemplo de la Tabla 4 del manual: Reporte X = 02 49 30 58 03 22
	got := trama([]byte("I0X"))
	want := []byte{0x02, 0x49, 0x30, 0x58, 0x03, 0x22}
	if string(got) != string(want) {
		t.Fatalf("trama = % X, se esperaba % X", got, want)
	}
}

func TestFormatos(t *testing.T) {
	e, d, _ := formatoPrecio(30)
	if s, _ := numFijo(1, e, d); s != "0000000000000100" {
		t.Fatalf("precio con flag 21=30: %s", s)
	}
	e, d, _ = formatoPrecio(0)
	if s, _ := numFijo(1, e, d); s != "0000000100" {
		t.Fatalf("precio con flag 21=00: %s", s)
	}
	ce, cd := formatoCantidad(30)
	if s, _ := numFijo(1, ce, cd); s != "00000000000001000" {
		t.Fatalf("cantidad con flag 21=30: %s", s)
	}
	if _, err := numFijo(1e9, 8, 2); err == nil {
		t.Fatal("un monto que no cabe debería dar error")
	}
	if texto("Losartán 50 mg · Caja x 30", 120) != "Losartan 50 mg - Caja x 30" {
		t.Fatal(texto("Losartán 50 mg · Caja x 30", 120))
	}
}

func TestEstado(t *testing.T) {
	im, _ := preparar(t)
	r := im.Estado()
	if r["ok"] != true || r["registro"] != "ZZP0000001" || r["modelo"] != "Aclas PP9 Plus" {
		t.Fatalf("estado: %v", r)
	}
	if r["flags"] != "21=30 50=00 63=01" || r["memoria"] != "4 % usada" {
		t.Fatalf("flags o memoria: %v", r)
	}
}

func TestEstadoSinPapelYApagada(t *testing.T) {
	im, sim := preparar(t)
	sim.SinPapel = true
	if r := im.Estado(); r["ok"] != false || r["error"] != "Sin papel" {
		t.Fatalf("sin papel: %v", r)
	}
	im2, sim2 := preparar(t)
	sim2.Apagada = true
	im2.e = nil
	ini := time.Now()
	r := im2.Estado()
	if r["ok"] != false || !strings.Contains(r["error"].(string), "no responde") {
		t.Fatalf("apagada: %v", r)
	}
	if time.Since(ini) > 30*time.Second {
		t.Fatal("con la impresora apagada tiene que responder en menos de 30 s")
	}
}

func TestFacturaYNoRepetir(t *testing.T) {
	im, sim := preparar(t)
	r := im.Documento(factura("a1"))
	if r["ok"] != true || r["numero"] != int64(1501) {
		t.Fatalf("factura: %v", r)
	}
	// Pago móvil parcial y el último (dólares) mayor que lo que falta: la impresora da el cambio.
	cmds := strings.Join(sim.Comandos, "|")
	if !strings.Contains(cmds, "|2030000000000050000|") || !strings.Contains(cmds, "|2020000000000030000|") {
		t.Fatalf("pagos mal armados: %s", cmds)
	}
	if !strings.Contains(cmds, "| 000000000003000000000000000002000Losartan 50 mg - Caja x 30|") {
		t.Fatalf("renglón exento mal armado: %s", cmds)
	}
	if strings.Contains(cmds, "iR*") {
		t.Fatal("al consumidor final no se le manda RIF")
	}
	// La caja reintenta el mismo id: no se imprime otra vez.
	n := len(sim.Comandos)
	r2 := im.Documento(factura("a1"))
	if r2["numero"] != int64(1501) || r2["repetida"] != true || len(sim.Comandos) != n {
		t.Fatalf("repetida: %v", r2)
	}
	if r3 := im.Documento(factura("a2")); r3["numero"] != int64(1502) {
		t.Fatalf("segunda factura: %v", r3)
	}
}

func TestPagoExactoVaComoPagoDirecto(t *testing.T) {
	im, sim := preparar(t)
	d := factura("b1")
	d.Pagos = []Pago{{Metodo: "Efectivo Bs", Monto: 700}, {Metodo: "Punto de venta", Monto: 16}}
	if r := im.Documento(d); r["ok"] != true {
		t.Fatalf("factura: %v", r)
	}
	ult := sim.Comandos[len(sim.Comandos)-1]
	if ult != "S1" {
		t.Fatalf("último comando: %s", ult)
	}
	cmds := strings.Join(sim.Comandos, "|")
	if !strings.Contains(cmds, "|2010000000000070000|104|") {
		t.Fatalf("el último pago debería ir como pago directo: %s", cmds)
	}
}

func TestTotalDistintoNoImprime(t *testing.T) {
	im, sim := preparar(t)
	d := factura("c1")
	d.Totales.Total = 730 // Cuadre calculó otra cosa (por ejemplo, otra tasa de IVA)
	r := im.Documento(d)
	if r["ok"] != false || !strings.Contains(r["error"].(string), "716.00") {
		t.Fatalf("debería negarse: %v", r)
	}
	if sim.doc != 0 || sim.ult[1] != 1500 {
		t.Fatal("la factura debería quedar anulada y sin número")
	}
}

func TestNotaDeCredito(t *testing.T) {
	im, sim := preparar(t)
	im.Documento(factura("f1"))
	nc := factura("n1")
	nc.Tipo = "NC"
	nc.Motivo = ptr("Devolución")
	nc.Afecta = &Afecta{Numero: ptr(int64(1501)), Fecha: "2026-11-26T10:00:00-04:00", Registro: ptr("ZZP0000001")}
	r := im.Documento(nc)
	if r["ok"] != true || r["numero"] != int64(41) {
		t.Fatalf("nota de crédito: %v", r)
	}
	cmds := strings.Join(sim.Comandos, "|")
	for _, w := range []string{"iF*00001501", "iD*26/11/2026", "iI*ZZP0000001", "iR*V-00000000", "iS*CONSUMIDOR FINAL", "|d0", "@MOTIVO: Devolucion"} {
		if !strings.Contains(cmds, w) {
			t.Fatalf("falta %q en %s", w, cmds)
		}
	}
	sinAfecta := factura("n2")
	sinAfecta.Tipo = "NC"
	if r := im.Documento(sinAfecta); r["ok"] != false {
		t.Fatalf("una nota sin factura afectada no se imprime: %v", r)
	}
}

func TestDocumentoAbiertoSeAnula(t *testing.T) {
	im, sim := preparar(t)
	im.conectar()
	sim.Write(trama([]byte(" 0000000000000100" + "00000000000001000" + "Quedo abierta")))
	sim.Purgar()
	if sim.doc != 1 {
		t.Fatal("el simulador debería tener una factura abierta")
	}
	if r := im.Documento(factura("d1")); r["ok"] != true || r["numero"] != int64(1501) {
		t.Fatalf("factura después de anular la abierta: %v", r)
	}
}

func TestReportes(t *testing.T) {
	im, _ := preparar(t)
	im.Documento(factura("x1"))
	nc := factura("x2")
	nc.Tipo = "NC"
	nc.Lineas = nc.Lineas[:1]
	nc.Lineas[0].Cantidad = 1
	nc.Totales = Totales{Exento: 300, Total: 300}
	nc.Pagos = []Pago{{Metodo: "Efectivo Bs", Monto: 300}}
	nc.Afecta = &Afecta{Numero: ptr(int64(1501)), Fecha: "2026-11-26T10:00:00-04:00"}
	if r := im.Documento(nc); r["ok"] != true {
		t.Fatalf("nc: %v", r)
	}
	x := im.Reporte(false)
	if x["ok"] != true || x["cant_fac"] != int64(1) || x["fac_desde"] != int64(1501) || x["cant_nc"] != int64(1) {
		t.Fatalf("reporte X: %v", x)
	}
	if x["exento"] != 300.0 || x["base_general"] != 100.0 || x["iva_general"] != 16.0 || x["total"] != 416.0 {
		t.Fatalf("montos del X: %v", x)
	}
	z := im.Reporte(true)
	if z["ok"] != true || z["numero"] != int64(87) || z["total"] != 416.0 {
		t.Fatalf("reporte Z: %v", z)
	}
	x2 := im.Reporte(false)
	if x2["cant_fac"] != int64(0) || x2["total"] != 0.0 || x2["fac_desde"] != nil {
		t.Fatalf("después del Z la jornada arranca en cero: %v", x2)
	}
}

func TestFlag50EnUnoCierraCon199(t *testing.T) {
	im, sim := preparar(t)
	sim.Flags[50] = 1
	if r := im.Documento(factura("g1")); r["ok"] != true {
		t.Fatalf("factura con flag 50=01: %v", r)
	}
	if !strings.Contains(strings.Join(sim.Comandos, "|"), "|199|") {
		t.Fatal("con el flag 50 en 01 hay que cerrar con 199")
	}
}

func TestFlag21EnCero(t *testing.T) {
	im, sim := preparar(t)
	sim.Flags[21] = 0
	if r := im.Documento(factura("h1")); r["ok"] != true {
		t.Fatalf("factura con flag 21=00: %v", r)
	}
	if !strings.Contains(strings.Join(sim.Comandos, "|"), "| 000003000000002000Losartan") {
		t.Fatal("con el flag 21 en 00 el precio va con 8+2 y la cantidad con 5+3")
	}
}

func TestMedios(t *testing.T) {
	c := configPorDefecto()
	casos := map[string]int{"Efectivo Bs": 1, "Efectivo USD": 2, "Efectivo $": 2, "Efectivo en dólares": 2, "Divisas": 2,
		"Pago móvil": 3, "Punto de venta": 4, "Transferencia": 5, "Zelle": 6, "Otro": 1}
	for m, n := range casos {
		if got := c.medio(m); got != n {
			t.Errorf("%s → %d, se esperaba %d", m, got, n)
		}
	}
}

func TestServidorCORSYSeguridad(t *testing.T) {
	im, _ := preparar(t)
	cfg := configPorDefecto()
	s := &Servidor{cfg: cfg, im: im, salir: func(int) {}}
	h := s.rutas()

	pide := func(metodo, ruta, origen, host, cuerpo string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(metodo, ruta, strings.NewReader(cuerpo))
		r.Host = host
		if origen != "" {
			r.Header.Set("Origin", origen)
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	w := pide("OPTIONS", "/documento", "https://josedanielgt1.github.io", "127.0.0.1:7123", "")
	if w.Code != 204 || w.Header().Get("Access-Control-Allow-Private-Network") != "true" ||
		w.Header().Get("Access-Control-Allow-Origin") != "https://josedanielgt1.github.io" {
		t.Fatalf("preflight: %d %v", w.Code, w.Header())
	}
	if w := pide("GET", "/estado", "https://otra-pagina.com", "127.0.0.1:7123", ""); w.Code != 403 {
		t.Fatalf("otra página no debería poder usar el agente: %d", w.Code)
	}
	if w := pide("GET", "/estado", "", "malo.com:7123", ""); w.Code != 403 {
		t.Fatalf("host ajeno: %d", w.Code)
	}
	if w := pide("POST", "/medios", "https://josedanielgt1.github.io", "127.0.0.1:7123", ""); w.Code != 403 {
		t.Fatalf("las herramientas solo desde la página del agente: %d", w.Code)
	}
	b, _ := json.Marshal(factura("s1"))
	w = pide("POST", "/documento", "https://josedanielgt1.github.io", "127.0.0.1:7123", string(b))
	var r map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &r)
	if r["ok"] != true || r["numero"] != 1501.0 {
		t.Fatalf("documento por HTTP: %s", w.Body.String())
	}
	if w := pide("GET", "/", "", "127.0.0.1:7123", ""); !strings.Contains(w.Body.String(), "Versión "+version) {
		t.Fatal("la página del agente debería decir su versión")
	}
	_ = http.StatusOK
}

func TestLecturasConYSinSeparadores(t *testing.T) {
	plano := []byte("S100" + f17(0) + f8(77) + "00003" + f8(0) + "00000" + f8(9) + "00001" + f8(0) + "00000" + "0012" + "0000" +
		"J123456789 " + "ZZP1234567" + "101010" + "261126")
	s := leerS1(plano)
	if s.UltFac != 77 || s.CantFac != 3 || s.UltNC != 9 || s.UltZ != 12 || s.Registro != "ZZP1234567" || s.RIF != "J123456789" {
		t.Fatalf("S1 sin separadores: %+v", s)
	}
	conLF := []byte(strings.Join([]string{"S100", f17(0), f8(77), "00003", f8(0), "00000", f8(9), "00001", f8(0), "00000", "0012", "0000", "J123456789", "ZZP1234567", "101010", "261126"}, "\n"))
	if s2 := leerS1(conLF); s2 != s {
		t.Fatalf("S1 con separadores: %+v", s2)
	}
}
