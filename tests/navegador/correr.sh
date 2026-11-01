#!/usr/bin/env bash
# Pruebas de las pantallas en Chromium, con un Supabase simulado (no toca la base real).
#   tests/navegador/correr.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 -m http.server 8765 >/dev/null 2>&1 & SRV=$!; trap 'kill $SRV 2>/dev/null || true' EXIT; sleep 1
for t in tests/navegador/*.test.js; do echo "=== $t"; node "$t"; done
