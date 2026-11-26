package main

// Lo que Cuadre le pide a la impresora: estado, factura o nota, Reporte X y Reporte Z.
// Contrato con la caja: docs/agente-maquina-fiscal.md.

import (
	"errors"
	"fmt"
	"math"
	"strings"
	"sync"
	"time"
)

var zonaVE = time.FixedZone("VET", -4*3600)

type Cliente struct {
	RIF    string  `json:"rif"`
	Nombre string  `json:"nombre"`
	Dir    *string `json:"dir"`
	Tel    *string `json:"tel"`
}

type Linea struct {
	Descripcion string  `json:"descripcion"`
	Cantidad    float64 `json:"cantidad"`
	Precio      float64 `json:"precio"`
	Alicuota    string  `json:"alicuota"`
}

type Pago struct {
	Metodo string  `json:"metodo"`
	Monto  float64 `json:"monto"`
}

type Totales struct {
	Exento       float64 `json:"exento"`
	BaseGeneral  float64 `json:"base_general"`
	IvaGeneral   float64 `json:"iva_general"`
	BaseReducida float64 `json:"base_reducida"`
	IvaReducida  float64 `json:"iva_reducida"`
	IGTF         float64 `json:"igtf"`
	Total        float64 `json:"total"`
}

type Afecta struct {
	Numero   *int64  `json:"numero"`
	Control  *string `json:"control"`
	Fecha    string  `json:"fecha"`
	Registro *string `json:"registro"`
}

type Documento struct {
	ID      string   `json:"id"`
	Tipo    string   `json:"tipo"`
	Fecha   string   `json:"fecha"`
	Cliente Cliente  `json:"cliente"`
	Lineas  []Linea  `json:"lineas"`
	Pagos   []Pago   `json:"pagos"`
	Totales Totales  `json:"totales"`
	Motivo  *string  `json:"motivo"`
	Afecta  *Afecta  `json:"afecta"`
	Pie     []string `json:"pie"`
}

type Respuesta map[string]any

func fallo(err error) Respuesta { return Respuesta{"ok": false, "error": mensaje(err)} }

func mensaje(err error) string {
	if errors.Is(err, errRechazado) {
		return "La impresora rechazó el comando. Revisa con Cuadre la configuración (flags y tasas)"
	}
	s := err.Error()
	if s == "" {
		return "Error de la impresora"
	}
	return strings.ToUpper(s[:1]) + s[1:]
}

// Info es lo que el agente sabe de la impresora conectada.
type Info struct {
	Codigo, Modelo, Registro, RIF string
	Flag21, Flag50, Flag63        int
	Tasas                         [3]float64
	FlagsLeidos                   bool
	Entrenamiento                 bool
}

type Impresora struct {
	mu       sync.Mutex
	cfg      *Config
	abrir    func() (Puerto, error)
	e        *Enlace
	puerto   Puerto
	info     Info
	impresos *Registro
	bit      func(string)
	pausa    func(time.Duration) // se reemplaza en las pruebas
}

func nuevaImpresora(cfg *Config, abrir func() (Puerto, error), reg *Registro, bit func(string)) *Impresora {
	if bit == nil {
		bit = func(string) {}
	}
	return &Impresora{cfg: cfg, abrir: abrir, impresos: reg, bit: bit, pausa: time.Sleep}
}

// conectar abre el puerto si hace falta y lee modelo, registro, RIF, tasas y flags.
func (im *Impresora) conectar() error {
	if im.e != nil {
		return nil
	}
	p, err := im.abrir()
	if err != nil {
		return err
	}
	e := nuevoEnlace(p, im.bit)
	sts1, _, err := e.Estado()
	if err != nil {
		p.Close()
		return err
	}
	info := Info{Flag21: im.cfg.Flag21, Flag50: im.cfg.Flag50, Flag63: 1, Entrenamiento: estadoEntrenamiento(sts1)}
	if d, err := e.Leer("SV"); err == nil {
		info.Codigo, info.Modelo = leerSV(d)
	}
	if d, err := e.Leer("S1"); err == nil {
		s := leerS1(d)
		info.Registro, info.RIF = s.Registro, s.RIF
	}
	if d, err := e.Leer("S3"); err == nil {
		if s3, err := leerS3(d); err == nil {
			info.Flag21, info.Flag50, info.Flag63 = s3.Flags[21], s3.Flags[50], s3.Flags[63]
			info.Tasas = s3.Tasas
			info.FlagsLeidos = true
		} else {
			im.bit("S3: " + err.Error())
		}
	}
	im.e, im.puerto, im.info = e, p, info
	im.bit(fmt.Sprintf("Conectada: %s %s, RIF %s, flags 21=%02d 50=%02d 63=%02d (leídos: %v)",
		info.Modelo, info.Registro, info.RIF, info.Flag21, info.Flag50, info.Flag63, info.FlagsLeidos))
	return nil
}

// soltar cierra el puerto para volver a abrirlo en el próximo pedido (por si desconectaron el USB).
func (im *Impresora) soltar() {
	if im.puerto != nil {
		im.puerto.Close()
	}
	im.e, im.puerto = nil, nil
}

func (im *Impresora) conErrores(f func() Respuesta) (r Respuesta) {
	defer func() {
		if x := recover(); x != nil {
			im.bit(fmt.Sprintf("PANIC: %v", x))
			im.soltar()
			r = Respuesta{"ok": false, "error": "Error interno del agente; intenta de nuevo"}
		}
	}()
	return f()
}

// esperarLibre consulta el estado hasta que la impresora termine de imprimir.
func (im *Impresora) esperarLibre(max time.Duration) (byte, byte, error) {
	limite := time.Now().Add(max)
	for {
		sts1, sts2, err := im.e.Estado()
		if err == nil && !estadoEnFiscal(sts1) && !estadoEnNoFiscal(sts1) {
			return sts1, sts2, nil
		}
		if time.Now().After(limite) {
			if err != nil {
				return 0, 0, err
			}
			return sts1, sts2, fmt.Errorf("la impresora sigue ocupada con un documento abierto")
		}
		im.pausa(300 * time.Millisecond)
	}
}

/* ---------------- GET /estado ---------------- */

func (im *Impresora) Estado() Respuesta {
	// Si está imprimiendo, no se hace esperar a la caja: está conectada y ocupada.
	if !im.mu.TryLock() {
		return Respuesta{"ok": true, "ocupada": true, "registro": im.info.Registro, "modelo": im.info.Modelo, "version": version}
	}
	defer im.mu.Unlock()
	return im.conErrores(func() Respuesta {
		if err := im.conectar(); err != nil {
			return fallo(err)
		}
		sts1, sts2, err := im.e.Estado()
		if err != nil {
			im.soltar()
			return fallo(err)
		}
		r := Respuesta{"ok": true, "registro": im.info.Registro, "modelo": im.info.Modelo, "rif": im.info.RIF,
			"version": version, "flags": fmt.Sprintf("21=%02d 50=%02d 63=%02d", im.info.Flag21, im.info.Flag50, im.info.Flag63)}
		if estadoEntrenamiento(sts1) {
			r["entrenamiento"] = true
			r["aviso"] = "La impresora está en modo entrenamiento: lo que imprime no es fiscal"
		}
		if memoriaLlena(sts1) {
			r["aviso"] = "La memoria fiscal está llena"
		}
		if d, err := im.e.Leer("S5"); err == nil {
			s5 := leerS5(d)
			if s5.CapacidadMB > 0 {
				usado := 100 - float64(s5.LibreMB)*100/float64(s5.CapacidadMB)
				r["memoria"] = fmt.Sprintf("%.0f %% usada", math.Max(0, usado))
			}
		}
		if t := textoError(sts2); t != "" {
			r["ok"], r["error"] = false, t
		}
		return r
	})
}

/* ---------------- POST /documento ---------------- */

func (im *Impresora) Documento(d Documento) Respuesta {
	im.mu.Lock()
	defer im.mu.Unlock()
	return im.conErrores(func() Respuesta {
		if d.ID == "" {
			return Respuesta{"ok": false, "error": "La factura llegó sin identificador"}
		}
		if prev, ok := im.impresos.Buscar(d.ID); ok {
			prev["ok"], prev["repetida"] = true, true
			return prev
		}
		if err := im.conectar(); err != nil {
			return fallo(err)
		}
		r, err := im.imprimirDocumento(d)
		if err != nil {
			if errors.Is(err, errSinRespuesta) {
				im.soltar()
			}
			return fallo(err)
		}
		return r
	})
}

func (im *Impresora) comandoItem(tipo, alicuota string) (string, error) {
	tasa := map[string]int{"E": 0, "G": 1, "R": 2, "A": 3}
	n, ok := tasa[strings.ToUpper(alicuota)]
	if !ok {
		return "", fmt.Errorf("alícuota desconocida «%s»", alicuota)
	}
	switch tipo {
	case "FAC":
		return string([]byte{" !\"#"[n]}), nil
	case "NC":
		return fmt.Sprintf("d%d", n), nil
	case "ND":
		return fmt.Sprintf("`%d", n), nil
	}
	return "", fmt.Errorf("tipo de documento desconocido «%s»", tipo)
}

func (im *Impresora) imprimirDocumento(d Documento) (Respuesta, error) {
	if len(d.Lineas) == 0 {
		return nil, fmt.Errorf("la factura no trae productos")
	}
	ent, dec, err := formatoPrecio(im.info.Flag21)
	if err != nil {
		return nil, err
	}
	cent, cdec := formatoCantidad(im.info.Flag21)

	sts1, sts2, err := im.e.Estado()
	if err != nil {
		return nil, err
	}
	if t := textoError(sts2); t != "" {
		return nil, errors.New(t)
	}
	if estadoEnFiscal(sts1) || estadoEnNoFiscal(sts1) {
		// Quedó un documento abierto (por ejemplo, se fue la luz): se anula antes de seguir.
		im.bit("Había un documento abierto: se anula")
		_ = im.e.Comando([]byte("7"))
		if _, _, err := im.esperarLibre(15 * time.Second); err != nil {
			return nil, fmt.Errorf("quedó un documento abierto en la impresora y no se pudo anular: %v", err)
		}
	}
	antes, err := im.e.Leer("S1")
	if err != nil {
		return nil, err
	}
	s1a := leerS1(antes)

	// 1. Cliente y, en las notas, la factura que corrigen.
	var cmds []string
	rif := texto(d.Cliente.RIF, 38)
	nombre := texto(d.Cliente.Nombre, 34)
	final := rif == "" || strings.Trim(strings.ToUpper(strings.ReplaceAll(rif, "-", "")), "V0") == ""
	if d.Tipo == "NC" || d.Tipo == "ND" {
		if d.Afecta == nil || d.Afecta.Numero == nil {
			return nil, fmt.Errorf("la nota no dice qué factura corrige")
		}
		f, err := time.Parse(time.RFC3339, d.Afecta.Fecha)
		if err != nil {
			return nil, fmt.Errorf("la fecha de la factura afectada no se entiende")
		}
		reg := im.info.Registro
		if d.Afecta.Registro != nil && *d.Afecta.Registro != "" {
			reg = *d.Afecta.Registro
		}
		if final {
			rif, nombre = "V-00000000", "CONSUMIDOR FINAL"
		}
		cmds = append(cmds, fmt.Sprintf("iF*%08d", *d.Afecta.Numero), "iD*"+f.In(zonaVE).Format("02/01/2006"),
			"iI*"+texto(reg, 20), "iR*"+rif, "iS*"+nombre)
	} else if !final {
		cmds = append(cmds, "iR*"+rif, "iS*"+nombre)
	}
	if d.Cliente.Dir != nil && *d.Cliente.Dir != "" {
		cmds = append(cmds, "i01DIR: "+texto(*d.Cliente.Dir, 34))
	}
	if d.Cliente.Tel != nil && *d.Cliente.Tel != "" {
		cmds = append(cmds, "i02TEL: "+texto(*d.Cliente.Tel, 34))
	}
	for _, c := range cmds {
		if err := im.e.Comando([]byte(c)); err != nil {
			return nil, fmt.Errorf("al mandar los datos del cliente: %w", err)
		}
	}

	// 2. Renglones.
	for i, l := range d.Lineas {
		cmd, err := im.comandoItem(d.Tipo, l.Alicuota)
		if err != nil {
			return nil, im.abortar(err)
		}
		pr, err := numFijo(l.Precio, ent, dec)
		if err != nil {
			return nil, im.abortar(err)
		}
		ca, err := numFijo(l.Cantidad, cent, cdec)
		if err != nil {
			return nil, im.abortar(err)
		}
		desc := texto(l.Descripcion, 120)
		if desc == "" {
			desc = "PRODUCTO"
		}
		if err := im.e.Comando([]byte(cmd + pr + ca + desc)); err != nil {
			return nil, im.abortar(fmt.Errorf("en el renglón %d (%s): %w", i+1, desc, err))
		}
	}

	// 3. Comentarios: motivo de la nota y pie (referencia en dólares y tasa BCV).
	var com []string
	if d.Motivo != nil && *d.Motivo != "" {
		com = append(com, "MOTIVO: "+*d.Motivo)
	}
	com = append(com, d.Pie...)
	for _, c := range com {
		if t := texto(c, 40); t != "" {
			if err := im.e.Comando([]byte("@" + t)); err != nil {
				im.bit("comentario no aceptado: " + err.Error())
			}
		}
	}

	// 4. Lo que calcula la impresora tiene que ser lo mismo que calculó Cuadre.
	dS2, err := im.e.Leer("S2")
	if err != nil {
		return nil, im.abortar(err)
	}
	s2 := leerS2(dS2)
	if math.Abs(s2.PorPagar-d.Totales.Total) > 0.05 {
		return nil, im.abortar(fmt.Errorf("la impresora calcula Bs %.2f y Cuadre Bs %.2f; no se imprimió (revisa las tasas de IVA de la impresora)", s2.PorPagar, d.Totales.Total))
	}

	// 5. Pagos. El último pago cierra el documento: si es mayor que lo que falta, la impresora calcula
	//    el cambio; si no, va como pago directo, que paga exactamente lo que falta (absorbe céntimos).
	pagos := []Pago{}
	for _, p := range d.Pagos {
		if p.Monto > 0 {
			pagos = append(pagos, p)
		}
	}
	if len(pagos) == 0 {
		pagos = []Pago{{Metodo: "Efectivo Bs", Monto: s2.PorPagar}}
	}
	suma := 0.0
	for _, p := range pagos {
		suma += p.Monto
	}
	for i, p := range pagos {
		medio := im.cfg.medio(p.Metodo)
		ultimo := i == len(pagos)-1
		var cmd string
		if ultimo && suma <= s2.PorPagar+0.05 {
			cmd = fmt.Sprintf("1%02d", medio)
		} else {
			m, err := numFijo(p.Monto, ent, dec)
			if err != nil {
				return nil, im.abortar(err)
			}
			cmd = fmt.Sprintf("2%02d%s", medio, m)
		}
		if err := im.e.Comando([]byte(cmd)); err != nil {
			return nil, fmt.Errorf("la impresora no aceptó el pago (%s): %w. Revisa la impresora: la factura puede haber quedado abierta", p.Metodo, err)
		}
	}
	// Con el flag 50 en 01 (IGTF) el documento se cierra con el comando 199.
	if im.info.Flag50 == 1 {
		if sts1, _, err := im.e.Estado(); err == nil && estadoEnFiscal(sts1) {
			if err := im.e.Comando([]byte("199")); err != nil {
				return nil, fmt.Errorf("la impresora no cerró la factura (comando 199): %w", err)
			}
		}
	}

	// 6. Esperar a que termine de imprimir y leer el número que le dio la memoria fiscal.
	if _, _, err := im.esperarLibre(25 * time.Second); err != nil {
		return nil, err
	}
	despues, err := im.e.Leer("S1")
	if err != nil {
		return nil, fmt.Errorf("la impresora imprimió, pero no se pudo leer el número: %w. Busca el número en el ticket", err)
	}
	s1 := leerS1(despues)
	numero, previo := s1.UltFac, s1a.UltFac
	switch d.Tipo {
	case "NC":
		numero, previo = s1.UltNC, s1a.UltNC
	case "ND":
		numero, previo = s1.UltND, s1a.UltND
	}
	if numero <= previo {
		return nil, fmt.Errorf("la impresora no registró el documento (el último número sigue en %d)", previo)
	}
	reg := s1.Registro
	if reg == "" {
		reg = im.info.Registro
	}
	r := Respuesta{"ok": true, "numero": numero, "registro": reg, "fecha": time.Now().In(zonaVE).Format(time.RFC3339)}
	if im.info.Entrenamiento {
		r["entrenamiento"] = true
	}
	if err := im.impresos.Guardar(d.ID, r); err != nil {
		im.bit("no se pudo guardar el registro de impresos: " + err.Error())
	}
	im.bit(fmt.Sprintf("Impreso %s %d (id %s)", d.Tipo, numero, d.ID))
	return r, nil
}

// abortar anula el documento en curso (antes de los pagos) y devuelve el error.
func (im *Impresora) abortar(err error) error {
	if sts1, _, e2 := im.e.Estado(); e2 == nil && estadoEnFiscal(sts1) {
		im.bit("Se anula el documento en curso: " + err.Error())
		_ = im.e.Comando([]byte("7"))
		_, _, _ = im.esperarLibre(10 * time.Second)
	}
	return err
}

/* ---------------- Reportes X y Z ---------------- */

func (im *Impresora) jornada(s1 datosS1, a acumulados) Respuesta {
	rango := func(ult, cant int64) (any, any) {
		if cant <= 0 {
			return nil, nil
		}
		return ult - cant + 1, ult
	}
	fd, fh := rango(s1.UltFac, s1.CantFac)
	cd, ch := rango(s1.UltNC, s1.CantNC)
	dd, dh := rango(s1.UltND, s1.CantND)
	ex := r2(a.Exento + a.NDExento - a.NCExento)
	bg := r2(a.BaseG + a.NDBaseG - a.NCBaseG)
	ig := r2(a.IvaG + a.NDIvaG - a.NCIvaG)
	br := r2(a.BaseR + a.NDBaseR - a.NCBaseR)
	ir := r2(a.IvaR + a.NDIvaR - a.NCIvaR)
	ba := r2(a.BaseA + a.NDBaseA - a.NCBaseA)
	ia := r2(a.IvaA + a.NDIvaA - a.NCIvaA)
	return Respuesta{"ok": true, "registro": im.info.Registro,
		"fac_desde": fd, "fac_hasta": fh, "cant_fac": s1.CantFac,
		"nc_desde": cd, "nc_hasta": ch, "cant_nc": s1.CantNC,
		"nd_desde": dd, "nd_hasta": dh, "cant_nd": s1.CantND,
		"exento": ex, "base_general": bg, "iva_general": ig, "base_reducida": br, "iva_reducida": ir,
		"total": r2(ex + bg + ig + br + ir + ba + ia)}
}

func (im *Impresora) leerJornada() (datosS1, acumulados, error) {
	d1, err := im.e.Leer("S1")
	if err != nil {
		return datosS1{}, acumulados{}, err
	}
	dx, err := im.e.Leer("U0X")
	if err != nil {
		return datosS1{}, acumulados{}, fmt.Errorf("no se pudieron leer los acumulados del día: %w", err)
	}
	return leerS1(d1), leerU0X(dx), nil
}

func (im *Impresora) Reporte(z bool) Respuesta {
	im.mu.Lock()
	defer im.mu.Unlock()
	return im.conErrores(func() Respuesta {
		if err := im.conectar(); err != nil {
			return fallo(err)
		}
		sts1, sts2, err := im.e.Estado()
		if err != nil {
			im.soltar()
			return fallo(err)
		}
		if t := textoError(sts2); t != "" {
			return Respuesta{"ok": false, "error": t}
		}
		if estadoEnFiscal(sts1) {
			return Respuesta{"ok": false, "error": "Hay una factura abierta en la impresora: termínala o anúlala antes del reporte"}
		}
		// Los acumulados se leen antes de imprimir: el Z los pone en cero.
		s1, acu, err := im.leerJornada()
		if err != nil {
			return fallo(err)
		}
		r := im.jornada(s1, acu)
		cmd := "I0X"
		if z {
			cmd = "I0Z"
		}
		if err := im.e.Comando([]byte(cmd)); err != nil {
			return fallo(err)
		}
		espera := 15 * time.Second
		if z {
			espera = 35 * time.Second // el manual pide esperar unos 20 s al reporte de transmisión
			im.pausa(3 * time.Second)
		}
		if _, _, err := im.esperarLibre(espera); err != nil {
			return fallo(err)
		}
		if z {
			numero := acu.ProximoZ
			if d, err := im.e.Leer("S1"); err == nil {
				if n := leerS1(d).UltZ; n > 0 {
					numero = n
				}
			}
			if numero <= 0 {
				return Respuesta{"ok": false, "error": "La impresora hizo el Reporte Z, pero no se pudo leer su número. Búscalo en el ticket"}
			}
			r["numero"] = numero
		}
		r["texto"] = textoReporte(z, r)
		return r
	})
}

func textoReporte(z bool, r Respuesta) string {
	t := "REPORTE X"
	if z {
		t = fmt.Sprintf("REPORTE Z N. %04d", r["numero"])
	}
	return fmt.Sprintf("%s\nFacturas: %v\nNotas de credito: %v\nExento Bs %.2f\nBase 16%% Bs %.2f\nIVA 16%% Bs %.2f\nBase 8%% Bs %.2f\nIVA 8%% Bs %.2f\nTotal neto Bs %.2f",
		t, r["cant_fac"], r["cant_nc"], r["exento"], r["base_general"], r["iva_general"], r["base_reducida"], r["iva_reducida"], r["total"])
}

/* ---------------- Herramientas de la página del agente ---------------- */

// Diagnostico junta las respuestas crudas de la impresora para mandárselas a Cuadre.
func (im *Impresora) Diagnostico() string {
	im.mu.Lock()
	defer im.mu.Unlock()
	var b strings.Builder
	fmt.Fprintf(&b, "Agente Cuadre %s · %s\n", version, time.Now().In(zonaVE).Format("02/01/2006 15:04"))
	fmt.Fprintf(&b, "Puerto: %s · paridad: %s · control de flujo: %v\n", im.cfg.Puerto, im.cfg.Paridad, im.cfg.ControlFlujo)
	if err := im.conectar(); err != nil {
		fmt.Fprintf(&b, "No se pudo conectar: %v\n", err)
		return b.String()
	}
	sts1, sts2, err := im.e.Estado()
	fmt.Fprintf(&b, "ENQ: estado 0x%02X, error 0x%02X, %v\n", sts1, sts2, err)
	for _, c := range []string{"SV", "S1", "S2", "S3", "S5", "U0X"} {
		d, err := im.e.Leer(c)
		if err != nil {
			fmt.Fprintf(&b, "%s: ERROR %v\n", c, err)
			continue
		}
		fmt.Fprintf(&b, "%s (%d): %s\n", c, len(d), visible(d))
	}
	i := im.info
	fmt.Fprintf(&b, "Leído: modelo %s (%s), registro %s, RIF %s, tasas %.2f/%.2f/%.2f, flags 21=%02d 50=%02d 63=%02d (leídos de la impresora: %v), entrenamiento: %v\n",
		i.Modelo, i.Codigo, i.Registro, i.RIF, i.Tasas[0], i.Tasas[1], i.Tasas[2], i.Flag21, i.Flag50, i.Flag63, i.FlagsLeidos, i.Entrenamiento)
	return b.String()
}

// ImprimirProgramacion manda el comando D: la impresora imprime tasas, medios de pago y flags.
func (im *Impresora) ImprimirProgramacion() Respuesta {
	im.mu.Lock()
	defer im.mu.Unlock()
	return im.conErrores(func() Respuesta {
		if err := im.conectar(); err != nil {
			return fallo(err)
		}
		if err := im.e.Comando([]byte("D")); err != nil {
			return fallo(err)
		}
		return Respuesta{"ok": true}
	})
}

// ProgramarMedios graba en la impresora los nombres de los medios de pago (comando PE).
func (im *Impresora) ProgramarMedios() Respuesta {
	im.mu.Lock()
	defer im.mu.Unlock()
	return im.conErrores(func() Respuesta {
		if err := im.conectar(); err != nil {
			return fallo(err)
		}
		hechos := []string{}
		for _, m := range im.cfg.Medios {
			if err := im.e.Comando([]byte(fmt.Sprintf("PE%02d%s", m.Numero, texto(m.Nombre, 14)))); err != nil {
				return Respuesta{"ok": false, "error": fmt.Sprintf("No se pudo programar el medio %02d (%s): %s. Puede que haga falta un Reporte Z antes", m.Numero, m.Nombre, mensaje(err)), "hechos": hechos}
			}
			hechos = append(hechos, fmt.Sprintf("%02d %s", m.Numero, m.Nombre))
		}
		return Respuesta{"ok": true, "hechos": hechos}
	})
}
