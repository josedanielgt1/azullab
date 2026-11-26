package main

// Impresora simulada que habla el mismo protocolo que la PP9 Plus según el manual V8.5.0.
// Sirve para las pruebas y para practicar con «-puerto sim». No reemplaza la prueba con la impresora real:
// las posiciones exactas de las respuestas hay que confirmarlas con el diagnóstico en el equipo.

import (
	"fmt"
	"math"
	"strconv"
	"strings"
	"sync"
	"time"
)

type itemSim struct {
	tasa         int // 0 exento, 1 general, 2 reducida, 3 adicional
	precio, cant float64
}

type acumSim struct{ ex, b1, i1, b2, i2, b3, i3 float64 }

type Simulador struct {
	mu            sync.Mutex
	salida        []byte
	entrada       []byte
	Apagada       bool
	Fiscal        bool
	Flags         map[int]int
	Tasas         [3]float64
	SinPapel      bool
	Registro, RIF string

	doc            int // 0 nada, 1 factura, 2 NC, 3 ND
	items          []itemSim
	pagado         float64
	pagos          int
	datosNC        map[string]bool
	ult            [4]int64 // [1] facturas, [2] NC, [3] ND
	cant           [4]int64
	ultZ           int64
	ventas, nc, nd acumSim
	Comandos       []string // lo que recibió, para las pruebas
}

func nuevoSimulador() *Simulador {
	return &Simulador{Fiscal: true, Flags: map[int]int{21: 30, 50: 0, 63: 1}, Tasas: [3]float64{16, 8, 31},
		Registro: "ZZP0000001", RIF: "J000000010", ult: [4]int64{0, 1500, 40, 0}, ultZ: 86, datosNC: map[string]bool{}}
}

func (s *Simulador) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.Apagada {
		return len(p), nil
	}
	s.entrada = append(s.entrada, p...)
	for len(s.entrada) > 0 {
		b := s.entrada[0]
		switch b {
		case cENQ:
			s.entrada = s.entrada[1:]
			s.responder([]byte{s.sts1(), s.sts2()}, cETX)
		case cACK, cNAK:
			s.entrada = s.entrada[1:]
		case cSTX:
			fin := -1
			for i := 1; i < len(s.entrada); i++ {
				if s.entrada[i] == cETX {
					fin = i
					break
				}
			}
			if fin < 0 || fin+1 >= len(s.entrada) {
				return len(p), nil // falta el resto de la trama
			}
			data := append([]byte{}, s.entrada[1:fin]...)
			lrc := s.entrada[fin+1]
			s.entrada = s.entrada[fin+2:]
			calc := byte(cETX)
			for _, x := range data {
				calc ^= x
			}
			if calc != lrc {
				s.salida = append(s.salida, cNAK)
				continue
			}
			s.Comandos = append(s.Comandos, string(data))
			s.procesar(string(data))
		default:
			s.entrada = s.entrada[1:]
		}
	}
	return len(p), nil
}

func (s *Simulador) LeerByte(espera time.Duration) (byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.salida) == 0 {
		return 0, errTiempo
	}
	b := s.salida[0]
	s.salida = s.salida[1:]
	return b, nil
}

func (s *Simulador) Purgar() error { s.mu.Lock(); s.salida = nil; s.mu.Unlock(); return nil }
func (s *Simulador) Close() error  { return nil }

func (s *Simulador) sts1() byte {
	base := byte(0x40)
	if s.Fiscal {
		base = 0x60
	}
	if s.doc > 0 {
		return base + 1
	}
	return base
}

func (s *Simulador) sts2() byte {
	if s.SinPapel {
		return 0x41
	}
	return 0x40
}

func (s *Simulador) responder(data []byte, fin byte) {
	lrc := fin
	for _, x := range data {
		lrc ^= x
	}
	s.salida = append(s.salida, cSTX)
	s.salida = append(s.salida, data...)
	s.salida = append(s.salida, fin, lrc)
}

func (s *Simulador) ack() { s.salida = append(s.salida, cACK) }
func (s *Simulador) nak() { s.salida = append(s.salida, cNAK) }

func (s *Simulador) formato() (int, int) {
	e, d, err := formatoPrecio(s.Flags[21])
	if err != nil {
		return 8, 2
	}
	return e, d
}

func num(t string, dec int) (float64, bool) {
	n, err := strconv.ParseInt(t, 10, 64)
	if err != nil {
		return 0, false
	}
	return float64(n) / math.Pow10(dec), true
}

func (s *Simulador) total() (bases, iva, total float64) {
	var b [4]float64
	for _, it := range s.items {
		b[it.tasa] += it.precio * it.cant
	}
	for i := range b {
		b[i] = r2(b[i])
	}
	iv := [4]float64{0, r2(b[1] * s.Tasas[0] / 100), r2(b[2] * s.Tasas[1] / 100), r2(b[3] * s.Tasas[2] / 100)}
	bases = b[0] + b[1] + b[2] + b[3]
	iva = iv[1] + iv[2] + iv[3]
	return bases, iva, r2(bases + iva)
}

func (s *Simulador) item(doc int, tasa int, resto string) {
	if s.SinPapel || (s.doc != 0 && s.doc != doc) || s.pagos > 0 {
		s.nak()
		return
	}
	if doc != 1 && !(s.datosNC["F"] && s.datosNC["D"] && s.datosNC["I"] && s.datosNC["R"] && s.datosNC["S"]) {
		s.nak() // la nota exige factura afectada, fecha, registro, RIF y razón social
		return
	}
	e, d := s.formato()
	ce, cd := formatoCantidad(s.Flags[21])
	if len(resto) < e+d+ce+cd {
		s.nak()
		return
	}
	pr, ok1 := num(resto[:e+d], d)
	ca, ok2 := num(resto[e+d:e+d+ce+cd], cd)
	if !ok1 || !ok2 || ca <= 0 {
		s.nak()
		return
	}
	s.doc = doc
	s.items = append(s.items, itemSim{tasa: tasa, precio: pr, cant: ca})
	s.ack()
}

func (s *Simulador) pagar(medio string, montoTxt string, directo bool) {
	if s.doc == 0 {
		s.nak()
		return
	}
	m, err := strconv.Atoi(medio)
	if err != nil || m < 1 || m > 24 || (m >= 20 && s.Flags[50] != 1) {
		s.nak()
		return
	}
	_, _, t := s.total()
	if directo {
		s.pagado = t
	} else {
		e, d := s.formato()
		if len(montoTxt) != e+d {
			s.nak()
			return
		}
		v, ok := num(montoTxt, d)
		if !ok {
			s.nak()
			return
		}
		s.pagado += v
	}
	s.pagos++
	s.ack()
	if s.pagado+0.001 >= t && s.Flags[50] != 1 {
		s.cerrar()
	}
}

func (s *Simulador) cerrar() {
	var b [4]float64
	for _, it := range s.items {
		b[it.tasa] += it.precio * it.cant
	}
	for i := range b {
		b[i] = r2(b[i])
	}
	a := acumSim{b[0], b[1], r2(b[1] * s.Tasas[0] / 100), b[2], r2(b[2] * s.Tasas[1] / 100), b[3], r2(b[3] * s.Tasas[2] / 100)}
	dst := &s.ventas
	if s.doc == 2 {
		dst = &s.nc
	} else if s.doc == 3 {
		dst = &s.nd
	}
	dst.ex += a.ex
	dst.b1 += a.b1
	dst.i1 += a.i1
	dst.b2 += a.b2
	dst.i2 += a.i2
	dst.b3 += a.b3
	dst.i3 += a.i3
	s.ult[s.doc]++
	s.cant[s.doc]++
	s.anularDoc()
}

func (s *Simulador) anularDoc() {
	s.doc, s.items, s.pagado, s.pagos = 0, nil, 0, 0
	s.datosNC = map[string]bool{}
}

func f8(n int64) string    { return fmt.Sprintf("%08d", n) }
func f17(v float64) string { return fmt.Sprintf("%017d", int64(math.Round(v*100))) }
func f18(v float64) string { return fmt.Sprintf("%018d", int64(math.Round(v*100))) }

func (s *Simulador) procesar(c string) {
	switch {
	case c == "SV":
		s.responder([]byte("SVZZPVE"), cETX)
	case c == "S1":
		_, _, t := s.total()
		r := "S100" + f17(t) + f8(s.ult[1]) + fmt.Sprintf("%05d", s.cant[1]) + f8(s.ult[3]) + fmt.Sprintf("%05d", s.cant[3]) +
			f8(s.ult[2]) + fmt.Sprintf("%05d", s.cant[2]) + f8(0) + "00000" + fmt.Sprintf("%04d", s.ultZ) + "0000" +
			fmt.Sprintf("%-11s", s.RIF) + fmt.Sprintf("%-10s", s.Registro) + "143000" + "251126"
		s.responder([]byte(r), cETX)
	case c == "S2":
		b, i, t := s.total()
		// Con separadores 0x0A, para probar ese camino de lectura.
		r := strings.Join([]string{"S2", f17(b), f17(i), f17(0), fmt.Sprintf("%017d", len(s.items)*1000), f17(r2(t - s.pagado)),
			fmt.Sprintf("%04d", s.pagos), strconv.Itoa(s.doc)}, "\n")
		s.responder([]byte(r), cETX)
	case c == "S3":
		r := "S3" + fmt.Sprintf("2%04d2%04d2%04d", int(s.Tasas[0]*100), int(s.Tasas[1]*100), int(s.Tasas[2]*100)) + "20300"
		for n := 0; n < 64; n++ {
			r += fmt.Sprintf("%02d", s.Flags[n])
		}
		s.responder([]byte(r), cETX)
	case c == "S5":
		s.responder([]byte("S5"+fmt.Sprintf("%-11s", s.RIF)+fmt.Sprintf("%-10s", s.Registro)+"0001"+"2048"+"1966"+"001234"), cETX)
	case c == "U0X":
		r := fmt.Sprintf("%04d", s.ultZ+1) + "251126" + "1800" + f8(s.ult[1]) + "251126" + "1430" + f8(s.ult[2]) + f8(s.ult[3]) + f8(0)
		for _, a := range []acumSim{s.ventas, s.nd, s.nc} {
			r += f18(a.ex) + f18(a.b1) + f18(a.i1) + f18(a.b2) + f18(a.i2) + f18(a.b3) + f18(a.i3)
		}
		r += strings.Repeat(f18(0), 10)
		// En dos bloques (ETB) y EOT, como la extracción de reportes.
		s.responder([]byte(r[:200]), cETB)
		s.responder([]byte(r[200:]), cETB)
		s.salida = append(s.salida, cEOT)
	case c == "I0X" || c == "D":
		if s.doc != 0 {
			s.nak()
			return
		}
		s.ack()
	case c == "I0Z":
		if s.doc != 0 {
			s.nak()
			return
		}
		s.ultZ++
		s.ventas, s.nc, s.nd = acumSim{}, acumSim{}, acumSim{}
		s.cant = [4]int64{}
		s.ack()
	case c == "7":
		if s.doc != 0 && s.pagos == 0 {
			s.anularDoc()
		}
		s.ack()
	case c == "199":
		_, _, t := s.total()
		if s.doc == 0 || s.Flags[50] != 1 || s.pagado+0.001 < t {
			s.nak()
			return
		}
		s.ack()
		s.cerrar()
	case c == "3":
		s.ack()
	case strings.HasPrefix(c, "PJ") && len(c) == 6:
		n, _ := strconv.Atoi(c[2:4])
		v, _ := strconv.Atoi(c[4:6])
		s.Flags[n] = v
		s.ack()
	case strings.HasPrefix(c, "PE"):
		s.ack()
	case strings.HasPrefix(c, "i"):
		if len(c) >= 3 && c[2] == '*' {
			s.datosNC[string(c[1])] = true
		}
		s.ack()
	case strings.HasPrefix(c, "@"):
		if s.doc == 0 {
			s.nak()
			return
		}
		s.ack()
	case len(c) > 1 && (c[0] == 'd' || c[0] == '`') && c[1] >= '0' && c[1] <= '3':
		doc := 2
		if c[0] == '`' {
			doc = 3
		}
		s.item(doc, int(c[1]-'0'), c[2:])
	case len(c) > 0 && strings.IndexByte(" !\"#", c[0]) >= 0:
		s.item(1, strings.IndexByte(" !\"#", c[0]), c[1:])
	case len(c) == 3 && c[0] == '1':
		s.pagar(c[1:3], "", true)
	case len(c) > 3 && c[0] == '2':
		s.pagar(c[1:3], c[3:], false)
	default:
		s.nak()
	}
}
