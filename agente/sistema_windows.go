//go:build windows

package main

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

var (
	k32              = syscall.NewLazyDLL("kernel32.dll")
	pGetCommState    = k32.NewProc("GetCommState")
	pSetCommState    = k32.NewProc("SetCommState")
	pSetCommTimeouts = k32.NewProc("SetCommTimeouts")
	pPurgeComm       = k32.NewProc("PurgeComm")
	u32              = syscall.NewLazyDLL("user32.dll")
	pMessageBox      = u32.NewProc("MessageBoxW")
)

/* ---------------- Puerto serial (también el USB, que Windows muestra como COM) ---------------- */

type dcb struct {
	DCBlength  uint32
	BaudRate   uint32
	Flags      uint32
	wReserved  uint16
	XonLim     uint16
	XoffLim    uint16
	ByteSize   byte
	Parity     byte
	StopBits   byte
	XonChar    byte
	XoffChar   byte
	ErrorChar  byte
	EofChar    byte
	EvtChar    byte
	wReserved1 uint16
}

type commTimeouts struct {
	ReadIntervalTimeout         uint32
	ReadTotalTimeoutMultiplier  uint32
	ReadTotalTimeoutConstant    uint32
	WriteTotalTimeoutMultiplier uint32
	WriteTotalTimeoutConstant   uint32
}

type serialWin struct{ h syscall.Handle }

func abrirSerial(nombre string, paridadPar bool, flujo bool) (Puerto, error) {
	ruta, err := syscall.UTF16PtrFromString(`\\.\` + nombre)
	if err != nil {
		return nil, err
	}
	h, err := syscall.CreateFile(ruta, syscall.GENERIC_READ|syscall.GENERIC_WRITE, 0, nil, syscall.OPEN_EXISTING, syscall.FILE_ATTRIBUTE_NORMAL, 0)
	if err != nil {
		return nil, fmt.Errorf("no se pudo abrir %s (¿lo está usando otro programa?): %v", nombre, err)
	}
	var d dcb
	d.DCBlength = uint32(unsafe.Sizeof(d))
	if r, _, e := pGetCommState.Call(uintptr(h), uintptr(unsafe.Pointer(&d))); r == 0 {
		syscall.CloseHandle(h)
		return nil, fmt.Errorf("%s no es un puerto serial: %v", nombre, e)
	}
	// 9600 bps, 8 bits, 1 bit de parada (Tabla 3 del manual de protocolos).
	d.BaudRate, d.ByteSize, d.StopBits = 9600, 8, 0
	f := uint32(1) // fBinary
	f |= 1 << 4    // DTR_CONTROL_ENABLE
	f |= 1 << 12   // RTS_CONTROL_ENABLE: la PC levanta RTS y la impresora responde con CTS
	if paridadPar {
		d.Parity = 2 // EVENPARITY
		f |= 1 << 1  // fParity
	} else {
		d.Parity = 0
	}
	if flujo {
		f |= 1 << 2 // fOutxCtsFlow
	}
	d.Flags = f
	if r, _, e := pSetCommState.Call(uintptr(h), uintptr(unsafe.Pointer(&d))); r == 0 {
		syscall.CloseHandle(h)
		return nil, fmt.Errorf("no se pudo configurar %s: %v", nombre, e)
	}
	// ReadFile vuelve enseguida si hay datos, o a los 100 ms si no llegó nada.
	t := commTimeouts{0xFFFFFFFF, 0xFFFFFFFF, 100, 0, 3000}
	if r, _, e := pSetCommTimeouts.Call(uintptr(h), uintptr(unsafe.Pointer(&t))); r == 0 {
		syscall.CloseHandle(h)
		return nil, fmt.Errorf("no se pudo configurar %s: %v", nombre, e)
	}
	s := &serialWin{h: h}
	_ = s.Purgar()
	return s, nil
}

func (s *serialWin) Write(b []byte) (int, error) {
	var n uint32
	err := syscall.WriteFile(s.h, b, &n, nil)
	if err == nil && int(n) < len(b) {
		err = io.ErrShortWrite
	}
	return int(n), err
}

func (s *serialWin) LeerByte(espera time.Duration) (byte, error) {
	limite := time.Now().Add(espera)
	buf := make([]byte, 1)
	for {
		var n uint32
		if err := syscall.ReadFile(s.h, buf, &n, nil); err != nil {
			return 0, fmt.Errorf("se perdió la conexión con la impresora: %v", err)
		}
		if n == 1 {
			return buf[0], nil
		}
		if time.Now().After(limite) {
			return 0, errTiempo
		}
	}
}

func (s *serialWin) Purgar() error {
	r, _, e := pPurgeComm.Call(uintptr(s.h), 0x0004|0x0008) // PURGE_TXCLEAR | PURGE_RXCLEAR
	if r == 0 {
		return e
	}
	return nil
}

func (s *serialWin) Close() error { return syscall.CloseHandle(s.h) }

func listarPuertos() []string {
	var out []string
	for i := 1; i <= 64; i++ {
		n := fmt.Sprintf("COM%d", i)
		ruta, _ := syscall.UTF16PtrFromString(`\\.\` + n)
		h, err := syscall.CreateFile(ruta, syscall.GENERIC_READ|syscall.GENERIC_WRITE, 0, nil, syscall.OPEN_EXISTING, 0, 0)
		if err == nil {
			syscall.CloseHandle(h)
			out = append(out, n)
		} else if err == syscall.ERROR_ACCESS_DENIED {
			out = append(out, n) // existe pero está ocupado; se intenta igual
		}
	}
	return out
}

/* ---------------- Instalación, arranque con Windows y supervisor ---------------- */

func carpetaInstalacion() string {
	base := os.Getenv("LOCALAPPDATA")
	if base == "" {
		base = filepath.Join(os.Getenv("USERPROFILE"), "AppData", "Local")
	}
	return filepath.Join(base, "CuadreAgente")
}

func sinVentana(c *exec.Cmd) *exec.Cmd {
	c.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000} // CREATE_NO_WINDOW
	return c
}

func arrancarWindows() int {
	exe, _ := os.Executable()
	destino := filepath.Join(carpetaInstalacion(), "CuadreAgente.exe")
	instalado := strings.EqualFold(filepath.Clean(exe), filepath.Clean(destino))

	if v := agenteCorriendo(); v != "" {
		if instalado || v == version {
			abrirNavegador("http://127.0.0.1:7123/")
			return 0
		}
		apagarAgente() // hay una versión distinta corriendo: se reemplaza
	}
	if !instalado {
		if err := instalar(exe, destino); err != nil {
			mostrarError("No se pudo instalar el agente: " + err.Error())
			return 1
		}
		if err := sinVentana(exec.Command(destino)).Start(); err != nil {
			mostrarError("Se instaló, pero no arrancó: " + err.Error())
			return 1
		}
		for i := 0; i < 20 && agenteCorriendo() == ""; i++ {
			time.Sleep(500 * time.Millisecond)
		}
		abrirNavegador("http://127.0.0.1:7123/")
		return 0
	}
	return supervisar(destino)
}

func instalar(origen, destino string) error {
	if err := os.MkdirAll(filepath.Dir(destino), 0o755); err != nil {
		return err
	}
	var err error
	for i := 0; i < 10; i++ { // si el anterior se está cerrando, el archivo puede seguir bloqueado un momento
		if err = copiar(origen, destino); err == nil {
			break
		}
		time.Sleep(500 * time.Millisecond)
	}
	if err != nil {
		return err
	}
	return sinVentana(exec.Command("reg", "add", `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`,
		"/v", "CuadreAgente", "/t", "REG_SZ", "/d", `"`+destino+`"`, "/f")).Run()
}

func quitarArranque() error {
	return sinVentana(exec.Command("reg", "delete", `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, "/v", "CuadreAgente", "/f")).Run()
}

func copiar(origen, destino string) error {
	in, err := os.Open(origen)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(destino + ".nuevo")
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	if err := out.Close(); err != nil {
		return err
	}
	return os.Rename(destino+".nuevo", destino)
}

// supervisar arranca el servidor y lo vuelve a arrancar si se cae.
func supervisar(exe string) int {
	for {
		c := sinVentana(exec.Command(exe, "-servir"))
		err := c.Run()
		codigo := 0
		if ee, ok := err.(*exec.ExitError); ok {
			codigo = ee.ExitCode()
		}
		if codigo == codigoApagar || codigo == 2 { // apagado pedido, o ya hay otro agente escuchando
			return 0
		}
		time.Sleep(3 * time.Second)
	}
}

func abrirNavegador(url string) {
	_ = sinVentana(exec.Command("rundll32", "url.dll,FileProtocolHandler", url)).Start()
}

func mostrarError(t string) {
	m, _ := syscall.UTF16PtrFromString(t)
	tit, _ := syscall.UTF16PtrFromString("Agente Cuadre")
	pMessageBox.Call(0, uintptr(unsafe.Pointer(m)), uintptr(unsafe.Pointer(tit)), 0x10)
}
