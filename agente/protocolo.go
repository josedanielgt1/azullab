package main

// Protocolo directo de las impresoras fiscales de The Factory HKA (Aclas PP9 Plus, HKA80 y otras).
// Fuente: «Manual de Protocolos y Comandos V8.5.0 – Venezuela» (23-08-2022), secciones 6 a 10.
//
//   Trama:  STX (0x02) + DATA + ETX (0x03) + LRC, donde LRC = XOR de DATA y ETX.
//   Respuesta a un comando simple: ACK (0x06) si lo aceptó, NAK (0x15) si no.
//   ENQ (0x05) devuelve STX + estado + error + ETX + LRC.
//   Los comandos de lectura devuelven una o varias tramas; las que terminan en ETB
//   esperan un ACK de la PC para mandar la siguiente, y la lectura termina con EOT.

import (
	"errors"
	"fmt"
	"strings"
	"time"
)

const (
	cSTX = 0x02
	cETX = 0x03
	cEOT = 0x04
	cENQ = 0x05
	cACK = 0x06
	cNAK = 0x15
	cETB = 0x17
)

// Puerto es la conexión física con la impresora (serial o USB en Windows, o el simulador).
type Puerto interface {
	Write(p []byte) (int, error)
	// LeerByte espera hasta «espera» por un byte; si no llega devuelve errTiempo.
	LeerByte(espera time.Duration) (byte, error)
	Purgar() error
	Close() error
}

var (
	errTiempo       = errors.New("tiempo agotado")
	errRechazado    = errors.New("la impresora rechazó el comando")
	errSinRespuesta = errors.New("La impresora no responde: revisa que esté encendida y conectada")
)

func trama(data []byte) []byte {
	lrc := byte(0)
	for _, b := range data {
		lrc ^= b
	}
	lrc ^= cETX
	out := make([]byte, 0, len(data)+3)
	out = append(out, cSTX)
	out = append(out, data...)
	return append(out, cETX, lrc)
}

// Enlace maneja el diálogo con la impresora sobre un Puerto.
type Enlace struct {
	p         Puerto
	esperaAck time.Duration // cuánto esperar el ACK o la primera respuesta
	bitacora  func(string)
}

func nuevoEnlace(p Puerto, bit func(string)) *Enlace {
	if bit == nil {
		bit = func(string) {}
	}
	return &Enlace{p: p, esperaAck: 3 * time.Second, bitacora: bit}
}

// Estado devuelve los dos bytes de ENQ: estado (STS1) y error (STS2).
func (e *Enlace) Estado() (byte, byte, error) {
	_ = e.p.Purgar()
	if _, err := e.p.Write([]byte{cENQ}); err != nil {
		return 0, 0, err
	}
	data, _, err := e.leerTrama(e.esperaAck)
	if err != nil {
		return 0, 0, err
	}
	if len(data) < 2 {
		return 0, 0, fmt.Errorf("respuesta de estado incompleta: %s", visible(data))
	}
	return data[0], data[1], nil
}

// Comando manda un comando simple y espera ACK. No se reintenta si no hay respuesta:
// la impresora pudo haberlo ejecutado (por ejemplo, un renglón de factura) y repetirlo lo duplicaría.
// Un NAK sí se reintenta una vez, porque un NAK quiere decir que no lo ejecutó.
func (e *Enlace) Comando(data []byte) error {
	for intento := 0; intento < 2; intento++ {
		_ = e.p.Purgar()
		e.bitacora("→ " + visible(data))
		if _, err := e.p.Write(trama(data)); err != nil {
			return err
		}
		b, err := e.p.LeerByte(e.esperaAck)
		if err == errTiempo {
			e.bitacora("← (sin respuesta)")
			return errSinRespuesta
		}
		if err != nil {
			return err
		}
		switch b {
		case cACK:
			e.bitacora("← ACK")
			return nil
		case cNAK:
			e.bitacora("← NAK")
			continue
		default:
			e.bitacora(fmt.Sprintf("← byte inesperado 0x%02X", b))
			return fmt.Errorf("la impresora respondió algo inesperado (0x%02X)", b)
		}
	}
	return errRechazado
}

// Leer manda un comando de lectura (S1, S2, S3, S5, SV, U0X…) y junta la respuesta.
func (e *Enlace) Leer(cmd string) ([]byte, error) {
	_ = e.p.Purgar()
	e.bitacora("→ " + cmd)
	if _, err := e.p.Write(trama([]byte(cmd))); err != nil {
		return nil, err
	}
	var todo []byte
	espera := e.esperaAck
	for {
		b, err := e.p.LeerByte(espera)
		if err == errTiempo {
			if len(todo) > 0 {
				return todo, nil
			}
			e.bitacora("← (sin respuesta)")
			return nil, errSinRespuesta
		}
		if err != nil {
			return nil, err
		}
		switch b {
		case cACK:
			continue // algunos modelos confirman el comando antes de responder
		case cNAK:
			e.bitacora("← NAK")
			return nil, errRechazado
		case cEOT:
			e.bitacora("← EOT")
			return todo, nil
		case cSTX:
			data, fin, err := e.cuerpo(espera)
			if err != nil {
				return nil, err
			}
			e.bitacora("← " + visible(data))
			todo = append(todo, data...)
			_, _ = e.p.Write([]byte{cACK})
			if fin == cETX {
				return todo, nil
			}
			espera = 2 * time.Second
		default:
			// ruido: se ignora
		}
	}
}

// leerTrama espera un STX y devuelve el contenido hasta ETX/ETB.
func (e *Enlace) leerTrama(espera time.Duration) ([]byte, byte, error) {
	limite := time.Now().Add(espera)
	for {
		resta := time.Until(limite)
		if resta <= 0 {
			return nil, 0, errSinRespuesta
		}
		b, err := e.p.LeerByte(resta)
		if err == errTiempo {
			return nil, 0, errSinRespuesta
		}
		if err != nil {
			return nil, 0, err
		}
		if b == cSTX {
			return e.cuerpo(espera)
		}
		if b == cNAK {
			return nil, 0, errRechazado
		}
	}
}

func (e *Enlace) cuerpo(espera time.Duration) ([]byte, byte, error) {
	var data []byte
	for {
		b, err := e.p.LeerByte(espera)
		if err == errTiempo {
			return nil, 0, fmt.Errorf("la respuesta de la impresora llegó cortada")
		}
		if err != nil {
			return nil, 0, err
		}
		if b == cETX || b == cETB {
			lrc, err := e.p.LeerByte(espera)
			if err != nil {
				return nil, 0, fmt.Errorf("la respuesta de la impresora llegó sin LRC")
			}
			calc := b
			for _, x := range data {
				calc ^= x
			}
			if calc != lrc {
				e.bitacora(fmt.Sprintf("LRC distinto: llegó 0x%02X, se esperaba 0x%02X", lrc, calc))
				// No se rechaza: algunos firmwares calculan el LRC sin el ETX. Queda en la bitácora.
			}
			return data, b, nil
		}
		data = append(data, b)
		if len(data) > 8192 {
			return nil, 0, fmt.Errorf("respuesta demasiado larga")
		}
	}
}

// visible muestra una trama con los bytes no imprimibles en hexadecimal (para la bitácora y el diagnóstico).
func visible(b []byte) string {
	var s strings.Builder
	for _, x := range b {
		if x >= 0x20 && x < 0x7F {
			s.WriteByte(x)
		} else {
			fmt.Fprintf(&s, "<%02X>", x)
		}
	}
	return s.String()
}

/* ---------- Estado y error (Tablas 7 y 8 del manual) ---------- */

func estadoEnEspera(sts1 byte) bool      { return sts1 == 0x40 || sts1 == 0x60 || sts1 == 0x68 }
func estadoEnFiscal(sts1 byte) bool      { return sts1 == 0x41 || sts1 == 0x61 || sts1 == 0x69 }
func estadoEnNoFiscal(sts1 byte) bool    { return sts1 == 0x42 || sts1 == 0x62 || sts1 == 0x6A }
func estadoEntrenamiento(sts1 byte) bool { return sts1&0xF0 == 0x40 }
func memoriaLlena(sts1 byte) bool        { return sts1 == 0x68 || sts1 == 0x69 || sts1 == 0x6A }

// textoError traduce el byte de error; "" si no hay error que impida imprimir.
func textoError(sts2 byte) string {
	switch sts2 {
	case 0x40, 0x48: // 0x48 es la gaveta: no impide imprimir
		return ""
	case 0x41:
		return "Sin papel"
	case 0x42:
		return "Error mecánico de la impresora o del papel (revisa la tapa)"
	case 0x43:
		return "Error mecánico de la impresora y sin papel"
	case 0x60:
		return "Error fiscal: llama al servicio técnico autorizado"
	case 0x64:
		return "Error de memoria fiscal: llama al servicio técnico autorizado"
	case 0x6C:
		return "La memoria fiscal está llena: llama al servicio técnico autorizado"
	default:
		return fmt.Sprintf("La impresora reporta el error 0x%02X", sts2)
	}
}
