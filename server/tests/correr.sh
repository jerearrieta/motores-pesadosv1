#!/usr/bin/env bash
# Crea una base de prueba, aplica las migraciones y corre las pruebas.
# Uso: server/tests/correr.sh   (necesita psql y un Postgres 15+ local)
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${DB:-mp_pruebas}
PSQL="psql -X -q -v ON_ERROR_STOP=1"
dropdb --if-exists "$DB" && createdb "$DB"
$PSQL -d "$DB" -f tests/stub_supabase.sql
for f in supabase/migrations/*.sql; do $PSQL -d "$DB" -f "$f"; done
$PSQL -d "$DB" -f tests/pruebas.sql
