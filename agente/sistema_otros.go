//go:build !windows

package main

import (
	"errors"
	"fmt"
	"os"
)

// Fuera de Windows el agente solo sirve con la impresora simulada (para desarrollo y pruebas).

func abrirSerial(nombre string, paridadPar bool, flujo bool) (Puerto, error) {
	return nil, errors.New("el puerto serial solo está hecho para Windows; usa -puerto sim para practicar")
}

func listarPuertos() []string { return nil }

func arrancarWindows() int { return correrServidor("") }

func quitarArranque() error { return nil }

func mostrarError(t string) { fmt.Fprintln(os.Stderr, t) }
