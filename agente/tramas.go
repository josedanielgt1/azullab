package main

// Formato de los montos que se mandan y lectura de las respuestas (S1, S2, S3, S5, SV, U0X).
// Las posiciones salen de las Tablas 22, 45, 46, 53, 55, 58 y 63 del manual V8.5.0.
// Si la respuesta trae separadores 0x0A se usan; si no, se corta por los anchos del manual.

import (
	"fmt"
	"math"
	"strconv"
	"strings"
	"unicode"
)

// formatoPrecio devuelve enteros y decimales del precio según el flag 21 (Tabla 22).
// El mismo formato vale para el monto de los pagos.
func formatoPrecio(flag21 int) (int, int, error) {
	switch flag21 {
	case 0:
		return 8, 2, nil
	case 1:
		return 7, 3, nil
	case 2:
		return 6, 4, nil
	case 11:
		return 9, 1, nil
	case 12:
		return 10, 0, nil
	case 30:
		return 14, 2, nil
	}
	return 0, 0, fmt.Errorf("el flag 21 está en %02d y el agente no conoce ese formato", flag21)
}

// formatoCantidad: 14 + 3 con el flag 21 en 30; 5 + 3 con los demás.
func formatoCantidad(flag21 int) (int, int) {
	if flag21 == 30 {
		return 14, 3
	}
	return 5, 3
}

// numFijo escribe un número sin coma, con ceros a la izquierda: 12,5 con (8,2) → "0000001250".
func numFijo(v float64, enteros, decimales int) (string, error) {
	if v < 0 {
		return "", fmt.Errorf("monto negativo")
	}
	n := int64(math.Round(v * math.Pow10(decimales)))
	s := strconv.FormatInt(n, 10)
	ancho := enteros + decimales
	if len(s) > ancho {
		return "", fmt.Errorf("el monto %.2f no cabe en la impresora", v)
	}
	return strings.Repeat("0", ancho-len(s)) + s, nil
}

// campos separa una respuesta en campos: por 0x0A si los trae, si no por anchos fijos.
func campos(data []byte, anchos []int) []string {
	s := string(data)
	if strings.Contains(s, "\n") {
		partes := strings.Split(s, "\n")
		out := make([]string, 0, len(partes))
		for _, p := range partes {
			out = append(out, strings.TrimSpace(p))
		}
		return out
	}
	out := []string{}
	pos := 0
	for _, a := range anchos {
		if pos >= len(s) {
			break
		}
		fin := pos + a
		if fin > len(s) {
			fin = len(s)
		}
		out = append(out, strings.TrimSpace(s[pos:fin]))
		pos = fin
	}
	return out
}

func entero(s string) int64 {
	var d strings.Builder
	for _, r := range s {
		if r >= '0' && r <= '9' {
			d.WriteRune(r)
		}
	}
	if d.Len() == 0 {
		return 0
	}
	n, _ := strconv.ParseInt(d.String(), 10, 64)
	return n
}

// monto lee un monto con dos decimales implícitos ("000000000001250" → 12,50).
func monto(s string) float64 {
	n := float64(entero(s)) / 100
	if strings.HasPrefix(strings.TrimSpace(s), "-") {
		n = -n
	}
	return n
}

func campo(c []string, i int) string {
	if i < len(c) {
		return c[i]
	}
	return ""
}

/* ---------- S1 (Tabla 45, modelos SRP812, HKA80, PP9, PP9-PLUS, TD1140) ---------- */

type datosS1 struct {
	UltFac, CantFac, UltND, CantND, UltNC, CantNC int64
	UltZ                                          int64
	RIF, Registro, Hora, Fecha                    string
}

var anchosS1 = []int{4, 17, 8, 5, 8, 5, 8, 5, 8, 5, 4, 4, 11, 10, 6, 6}

func leerS1(data []byte) datosS1 {
	c := campos(data, anchosS1)
	return datosS1{
		UltFac: entero(campo(c, 2)), CantFac: entero(campo(c, 3)),
		UltND: entero(campo(c, 4)), CantND: entero(campo(c, 5)),
		UltNC: entero(campo(c, 6)), CantNC: entero(campo(c, 7)),
		UltZ: entero(campo(c, 10)),
		RIF:  campo(c, 12), Registro: strings.ToUpper(campo(c, 13)), Hora: campo(c, 14), Fecha: campo(c, 15),
	}
}

/* ---------- S2 (Tabla 46): documento en curso ---------- */

type datosS2 struct {
	Bases, Impuesto, PorPagar float64
	Pagos                     int64
	Tipo                      int64 // 0 ninguno, 1 factura, 2 NC, 3 ND
}

var anchosS2 = []int{2, 17, 17, 17, 17, 17, 4, 1}

func leerS2(data []byte) datosS2 {
	c := campos(data, anchosS2)
	return datosS2{Bases: monto(campo(c, 1)), Impuesto: monto(campo(c, 2)), PorPagar: monto(campo(c, 5)),
		Pagos: entero(campo(c, 6)), Tipo: entero(campo(c, 7))}
}

/* ---------- S3 (Tabla 53): tasas y flags ---------- */

type datosS3 struct {
	Tasas [3]float64
	Flags map[int]int
}

func leerS3(data []byte) (datosS3, error) {
	s := strings.ReplaceAll(string(data), "\n", "")
	d := datosS3{Flags: map[int]int{}}
	if len(s) < 2+15+128 {
		return d, fmt.Errorf("el status S3 llegó corto (%d caracteres)", len(s))
	}
	// Tras "S3": tipo (1) + valor (4) por cada tasa.
	for i := 0; i < 3; i++ {
		ini := 2 + i*5
		d.Tasas[i] = float64(entero(s[ini+1:ini+5])) / 100
	}
	// Los 64 flags (00 a 63), dos dígitos cada uno, van al final de la trama.
	bloque := s[len(s)-128:]
	for n := 0; n < 64; n++ {
		v, err := strconv.Atoi(bloque[2*n : 2*n+2])
		if err != nil {
			return d, fmt.Errorf("no se pudieron leer los flags del status S3")
		}
		d.Flags[n] = v
	}
	return d, nil
}

/* ---------- S5 (Tabla 55): memoria de auditoría ---------- */

type datosS5 struct {
	RIF, Serial          string
	CapacidadMB, LibreMB int64
}

func leerS5(data []byte) datosS5 {
	c := campos(data, []int{2, 11, 10, 4, 4, 4, 6})
	return datosS5{RIF: campo(c, 1), Serial: campo(c, 2), CapacidadMB: entero(campo(c, 4)), LibreMB: entero(campo(c, 5))}
}

/* ---------- SV (Tabla 58): modelo ---------- */

var modelos = map[string]string{
	"ZZP": "Aclas PP9 Plus", "ZZH": "Aclas PP9", "Z7C": "HKA80", "Z7A": "HKA112", "Z1F": "SRP-812",
	"Z1B": "SRP-350", "Z1E": "SRP-280", "ZPA": "HSP7000", "Z6A": "Tally 1125", "Z6B": "DT-230",
	"Z6C": "Tally 1140", "ZYA": "P3100DL", "Z1A": "SRP-270",
}

func leerSV(data []byte) (codigo, nombre string) {
	s := strings.ToUpper(string(data))
	for c, n := range modelos {
		if strings.Contains(s, c) {
			return c, n
		}
	}
	return "", strings.TrimSpace(strings.TrimPrefix(s, "SV"))
}

/* ---------- U0X / U0Z (Tabla 63): acumulados de la jornada ---------- */

type acumulados struct {
	ProximoZ                                                    int64
	Exento, BaseG, IvaG, BaseR, IvaR, BaseA, IvaA               float64 // ventas
	NDExento, NDBaseG, NDIvaG, NDBaseR, NDIvaR, NDBaseA, NDIvaA float64
	NCExento, NCBaseG, NCIvaG, NCBaseR, NCIvaR, NCBaseA, NCIvaA float64
}

func leerU0X(data []byte) acumulados {
	var c []string
	if strings.Contains(string(data), "\n") {
		c = campos(data, nil)
	} else {
		// 9 campos de cabecera (56 caracteres) y después montos de 18 (o 17) caracteres.
		cab := []int{4, 6, 4, 8, 6, 4, 8, 8, 8}
		resto := len(data) - 56
		ancho := 18
		if resto > 0 && resto%18 != 0 && resto%17 == 0 {
			ancho = 17
		}
		anchos := append([]int{}, cab...)
		for i := 0; i < 40; i++ {
			anchos = append(anchos, ancho)
		}
		c = campos(data, anchos)
	}
	m := func(i int) float64 { return monto(campo(c, i)) }
	return acumulados{
		ProximoZ: entero(campo(c, 0)),
		Exento:   m(9), BaseG: m(10), IvaG: m(11), BaseR: m(12), IvaR: m(13), BaseA: m(14), IvaA: m(15),
		NDExento: m(16), NDBaseG: m(17), NDIvaG: m(18), NDBaseR: m(19), NDIvaR: m(20), NDBaseA: m(21), NDIvaA: m(22),
		NCExento: m(23), NCBaseG: m(24), NCIvaG: m(25), NCBaseR: m(26), NCIvaR: m(27), NCBaseA: m(28), NCIvaA: m(29),
	}
}

/* ---------- Texto que va a la impresora ---------- */

var sinAcento = strings.NewReplacer("á", "a", "é", "e", "í", "i", "ó", "o", "ú", "u", "ü", "u", "ñ", "n",
	"Á", "A", "É", "E", "Í", "I", "Ó", "O", "Ú", "U", "Ü", "U", "Ñ", "N", "·", "-", "°", "o", "º", "o", "ª", "a",
	"–", "-", "—", "-", "“", "\"", "”", "\"", "‘", "'", "’", "'", "×", "x")

// texto deja solo caracteres que la impresora imprime bien y corta al máximo de su campo.
func texto(s string, max int) string {
	s = sinAcento.Replace(s)
	var b strings.Builder
	for _, r := range s {
		if r >= 0x20 && r < 0x7F {
			b.WriteRune(r)
		} else if unicode.IsSpace(r) {
			b.WriteByte(' ')
		}
	}
	t := strings.TrimSpace(b.String())
	if len(t) > max {
		t = strings.TrimSpace(t[:max])
	}
	return t
}

func r2(v float64) float64 { return math.Round(v*100) / 100 }
