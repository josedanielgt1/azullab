package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

type Medio struct {
	Numero int    `json:"numero"`
	Nombre string `json:"nombre"`
	// Palabras que, si aparecen en el nombre del método de Cuadre, mandan el pago a este medio.
	Claves []string `json:"claves"`
}

type Config struct {
	Puerto       string   `json:"puerto"`        // "auto", "COM3"… o "sim" para practicar
	Paridad      string   `json:"paridad"`       // "auto", "par" o "ninguna"
	ControlFlujo bool     `json:"control_flujo"` // RTS/CTS
	Escucha      string   `json:"escucha"`       // siempre 127.0.0.1
	Origenes     []string `json:"origenes"`      // páginas que pueden usar el agente
	// Si la impresora no deja leer sus flags (status S3), se usan estos.
	Flag21 int     `json:"flag21"`
	Flag50 int     `json:"flag50"`
	Medios []Medio `json:"medios"`
	// Dónde se encontró la impresora la última vez (se prueba primero).
	UltimoPuerto  string `json:"ultimo_puerto,omitempty"`
	UltimaParidad string `json:"ultima_paridad,omitempty"`
	archivo       string
}

func configPorDefecto() *Config {
	return &Config{
		Puerto: "auto", Paridad: "auto", Escucha: "127.0.0.1:7123",
		Origenes: []string{"https://josedanielgt1.github.io"},
		Flag21:   30, Flag50: 0,
		Medios: []Medio{
			{1, "EFECTIVO BS", []string{"efectivo bs", "efectivo en la farmacia", "bolivar"}},
			{2, "EFECTIVO USD", []string{"usd", "$", "dolar", "dólar", "divisa"}},
			{3, "PAGO MOVIL", []string{"movil", "móvil"}},
			{4, "PUNTO VENTA", []string{"punto", "tarjeta", "debito", "débito"}},
			{5, "TRANSFERENCIA", []string{"transfer"}},
			{6, "ZELLE", []string{"zelle"}},
		},
	}
}

// cargarConfig lee agente.json de la carpeta del agente; si no existe, lo crea con los valores por defecto.
func cargarConfig(dir string) (*Config, error) {
	c := configPorDefecto()
	c.archivo = filepath.Join(dir, "agente.json")
	b, err := os.ReadFile(c.archivo)
	if os.IsNotExist(err) {
		return c, c.guardar()
	}
	if err != nil {
		return nil, err
	}
	if err := json.Unmarshal(b, c); err != nil {
		return nil, err
	}
	if c.Escucha == "" || !strings.HasPrefix(c.Escucha, "127.0.0.1:") {
		c.Escucha = "127.0.0.1:7123" // nunca en la red
	}
	return c, nil
}

func (c *Config) guardar() error {
	if c.archivo == "" {
		return nil
	}
	b, _ := json.MarshalIndent(c, "", "  ")
	return escribirSeguro(c.archivo, b)
}

// medio devuelve el número de medio de pago de la impresora para un método de Cuadre.
func (c *Config) medio(metodo string) int {
	m := strings.ToLower(metodo)
	// Primero las claves más específicas (dólares antes que «efectivo»).
	for _, md := range c.Medios {
		if md.Numero == 1 {
			continue
		}
		for _, k := range md.Claves {
			if k != "" && strings.Contains(m, strings.ToLower(k)) {
				return md.Numero
			}
		}
	}
	for _, md := range c.Medios {
		if md.Numero == 1 {
			return 1
		}
	}
	return 1
}

func (c *Config) origenPermitido(o string) bool {
	if o == "" {
		return true
	}
	if o == "http://"+c.Escucha || o == "http://localhost:"+strings.TrimPrefix(c.Escucha, "127.0.0.1:") {
		return true
	}
	for _, p := range c.Origenes {
		if strings.EqualFold(strings.TrimRight(p, "/"), o) {
			return true
		}
	}
	return false
}

/* ---------- Registro de lo impreso: evita imprimir dos veces el mismo documento ---------- */

type Registro struct {
	mu      sync.Mutex
	archivo string
	datos   map[string]Respuesta
}

func abrirRegistro(archivo string) *Registro {
	r := &Registro{archivo: archivo, datos: map[string]Respuesta{}}
	if archivo != "" {
		if b, err := os.ReadFile(archivo); err == nil {
			_ = json.Unmarshal(b, &r.datos)
		}
	}
	return r
}

func (r *Registro) Buscar(id string) (Respuesta, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	v, ok := r.datos[id]
	if !ok {
		return nil, false
	}
	c := Respuesta{}
	for k, x := range v {
		c[k] = x
	}
	return c, true
}

func (r *Registro) Guardar(id string, v Respuesta) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	c := Respuesta{}
	for k, x := range v {
		if k != "ok" {
			c[k] = x
		}
	}
	r.datos[id] = c
	if r.archivo == "" {
		return nil
	}
	b, _ := json.MarshalIndent(r.datos, "", " ")
	return escribirSeguro(r.archivo, b)
}

func escribirSeguro(archivo string, b []byte) error {
	tmp := archivo + ".tmp"
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, archivo)
}
