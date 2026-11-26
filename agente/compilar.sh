#!/usr/bin/env bash
# Compila el agente para Windows (sirve en 32 y 64 bits) y corre sus pruebas.
#   agente/compilar.sh   →   agente/dist/CuadreAgente.exe
set -euo pipefail
cd "$(dirname "$0")"
go vet ./... && go test ./...
mkdir -p dist
GOOS=windows GOARCH=386 CGO_ENABLED=0 go build -trimpath -ldflags "-H windowsgui -s -w" -o dist/CuadreAgente.exe .
echo "Listo: agente/dist/CuadreAgente.exe"
