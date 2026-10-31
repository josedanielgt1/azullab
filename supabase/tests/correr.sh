#!/usr/bin/env bash
# Prueba las migraciones en un Postgres local. Cada archivo de pruebas corre en una base nueva.
#   PGHOST=/tmp/pg PGPORT=5433 PGUSER=postgres supabase/tests/correr.sh
set -euo pipefail
cd "$(dirname "$0")/.."
BD=cuadre_prueba
for t in tests/0*_test.sql; do
  dropdb --if-exists "$BD" 2>/dev/null; createdb "$BD"
  psql -q -v ON_ERROR_STOP=1 -d "$BD" -f tests/00_stub_supabase.sql
  for m in migrations/*.sql; do psql -q -v ON_ERROR_STOP=1 -d "$BD" -f "$m"; done
  echo "=== $t"
  psql -tA -v ON_ERROR_STOP=1 -d "$BD" -f "$t" 2>&1 | sed -n 's/^psql:[^ ]* NOTICE:  /  /p; /^---/p; /ERROR/p'
done
