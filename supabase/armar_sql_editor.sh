#!/usr/bin/env bash
# Arma un solo archivo para pegar en el SQL Editor con las migraciones desde un número.
#   supabase/armar_sql_editor.sh 0003 > supabase/pendiente_sql_editor.sql
set -euo pipefail
cd "$(dirname "$0")"
desde=${1:?número de la primera migración, por ejemplo 0003}
echo "-- Cuadre · Para pegar en el SQL Editor de Supabase (proyecto azullab) y darle Run una vez."
echo "-- Migraciones desde la $desde. Generado por supabase/armar_sql_editor.sh; no editar a mano."
vals=()
for m in migrations/*.sql; do
  n=$(basename "$m" .sql); v=${n%%_*}
  [[ "$v" < "$desde" ]] && continue
  echo; echo "-- >>>>> $m"; cat "$m"; vals+=("('$v', '${n#*_}')")
done
echo
echo "-- >>>>> Historial de migraciones"
echo "insert into supabase_migrations.schema_migrations (version, name) values"
(IFS=,; echo "  ${vals[*]}")
echo "on conflict (version) do nothing;"
echo "select 'Listo: migraciones aplicadas' as resultado;"
