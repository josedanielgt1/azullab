// Agente de la impresora fiscal de Cuadre.
//
// La caja de Cuadre es una página web y no puede hablar con el puerto USB o serial.
// Este programa corre en la computadora de la caja, escucha solo en http://127.0.0.1:7123
// y le pasa a la impresora fiscal (protocolo de The Factory HKA) lo que le pide la caja.
//
// Uso en Windows: doble clic en CuadreAgente.exe. Se copia a %LOCALAPPDATA%\CuadreAgente,
// queda arrancando con Windows y abre su página en el navegador. Ver agente/LEEME.md.
package main

import (
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

const version = "1.0.0"

// Código de salida con el que el servidor le pide al supervisor que no lo vuelva a arrancar.
const codigoApagar = 3

var dirDatos string

func rutaDatos(nombre string) string { return filepath.Join(dirDatos, nombre) }

func main() {
	servir := flag.Bool("servir", false, "atender a la caja (lo usa el supervisor)")
	puerto := flag.String("puerto", "", "puerto de la impresora: auto, COM3… o sim (impresora simulada)")
	desinstalar := flag.Bool("desinstalar", false, "quitar el arranque con Windows")
	dir := flag.String("dir", "", "carpeta de configuración y registros (por defecto, la del programa)")
	flag.Parse()

	dirDatos = *dir
	if dirDatos == "" {
		exe, _ := os.Executable()
		dirDatos = filepath.Dir(exe)
	}

	if *desinstalar {
		if err := quitarArranque(); err != nil {
			mostrarError("No se pudo quitar el arranque con Windows: " + err.Error())
			os.Exit(1)
		}
		apagarAgente()
		return
	}
	if *servir || runtime.GOOS != "windows" {
		os.Exit(correrServidor(*puerto))
	}
	// Windows, doble clic o arranque con la sesión.
	os.Exit(arrancarWindows())
}

func correrServidor(puertoForzado string) int {
	cfg, err := cargarConfig(dirDatos)
	if err != nil {
		mostrarError("No se pudo leer agente.json: " + err.Error())
		return 1
	}
	if puertoForzado != "" {
		cfg.Puerto = puertoForzado
	}
	bit := bitacora(rutaDatos("agente.log"))
	bit(fmt.Sprintf("Agente %s arrancando · puerto %s · escucha %s", version, cfg.Puerto, cfg.Escucha))

	var sim *Simulador
	abrir := func() (Puerto, error) {
		if strings.EqualFold(cfg.Puerto, "sim") {
			if sim == nil {
				sim = nuevoSimulador()
			}
			return sim, nil
		}
		return abrirImpresora(cfg, bit)
	}
	im := nuevaImpresora(cfg, abrir, abrirRegistro(rutaDatos("impresos.json")), bit)

	ln, err := net.Listen("tcp", cfg.Escucha)
	if err != nil {
		bit("No se pudo escuchar en " + cfg.Escucha + ": " + err.Error())
		return 2
	}
	s := &Servidor{cfg: cfg, im: im, salir: func(c int) { bit("Apagado pedido desde la página"); os.Exit(c) }}
	srv := &http.Server{Handler: s.rutas(), ReadHeaderTimeout: 10 * time.Second}
	bit("Listo en http://" + cfg.Escucha)
	if err := srv.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
		bit("El servidor se cayó: " + err.Error())
		return 1
	}
	return 0
}

// abrirImpresora busca la impresora: el puerto configurado o, en «auto», todos los COM.
// Con paridad «auto» prueba par (manual de protocolos) y después ninguna (manual de usuario).
func abrirImpresora(cfg *Config, bit func(string)) (Puerto, error) {
	puertos := []string{cfg.Puerto}
	if cfg.Puerto == "" || strings.EqualFold(cfg.Puerto, "auto") {
		puertos = listarPuertos()
		if cfg.UltimoPuerto != "" {
			puertos = append([]string{cfg.UltimoPuerto}, puertos...)
		}
		if len(puertos) == 0 {
			return nil, errors.New("No hay ningún puerto COM en esta computadora: revisa el cable USB y el driver de la impresora")
		}
	}
	paridades := []string{"par", "ninguna"}
	switch strings.ToLower(cfg.Paridad) {
	case "par":
		paridades = []string{"par"}
	case "ninguna":
		paridades = []string{"ninguna"}
	default:
		if cfg.UltimaParidad == "ninguna" {
			paridades = []string{"ninguna", "par"}
		}
	}
	vistos := map[string]bool{}
	var ultimo error
	for _, nombre := range puertos {
		if vistos[nombre] {
			continue
		}
		vistos[nombre] = true
		for _, par := range paridades {
			p, err := abrirSerial(nombre, par == "par", cfg.ControlFlujo)
			if err != nil {
				ultimo = fmt.Errorf("%s: %v", nombre, err)
				continue
			}
			e := nuevoEnlace(p, nil)
			e.esperaAck = 800 * time.Millisecond
			if _, _, err := e.Estado(); err == nil {
				bit(fmt.Sprintf("Impresora encontrada en %s (paridad %s)", nombre, par))
				if cfg.UltimoPuerto != nombre || cfg.UltimaParidad != par {
					cfg.UltimoPuerto, cfg.UltimaParidad = nombre, par
					_ = cfg.guardar()
				}
				return p, nil
			}
			p.Close()
			ultimo = fmt.Errorf("%s no responde", nombre)
		}
	}
	if ultimo == nil {
		ultimo = errSinRespuesta
	}
	return nil, fmt.Errorf("No se encontró la impresora (%v). Revisa que esté encendida y conectada", ultimo)
}

func bitacora(archivo string) func(string) {
	if fi, err := os.Stat(archivo); err == nil && fi.Size() > 5<<20 {
		_ = os.Rename(archivo, archivo+".anterior")
	}
	f, err := os.OpenFile(archivo, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return func(s string) { log.Println(s) }
	}
	l := log.New(f, "", log.LstdFlags)
	return func(s string) {
		l.Println(s)
		if runtime.GOOS != "windows" {
			log.Println(s)
		}
	}
}

// agenteCorriendo devuelve la versión del agente que ya atiende en 127.0.0.1:7123, o "".
func agenteCorriendo() string {
	c := http.Client{Timeout: 1500 * time.Millisecond}
	r, err := c.Get("http://127.0.0.1:7123/")
	if err != nil {
		return ""
	}
	defer r.Body.Close()
	b := make([]byte, 2048)
	n, _ := r.Body.Read(b)
	s := string(b[:n])
	if i := strings.Index(s, "Versión "); i >= 0 {
		v := s[i+len("Versión "):]
		if j := strings.IndexAny(v, " <·"); j > 0 {
			return v[:j]
		}
	}
	return "?"
}

func apagarAgente() {
	c := http.Client{Timeout: 2 * time.Second}
	if r, err := c.Post("http://127.0.0.1:7123/apagar", "application/json", nil); err == nil {
		r.Body.Close()
		time.Sleep(1500 * time.Millisecond)
	}
}
