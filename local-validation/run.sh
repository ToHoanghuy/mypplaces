#!/usr/bin/env bash
# Reproducible local validation on plain PostgreSQL (no Docker / Supabase CLI needed).
# Usage: PGBIN=/path/to/pg/bin ./run.sh   (server must already be running; see README)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SB="${SB_DIR:-$HERE/../supabase}"
PGHOST="${PGHOST:-/tmp}"; PGPORT="${PGPORT:-54329}"; PGUSER="${PGUSER:-postgres}"
DB="${DB:-myplaces_test}"
P="psql -X -q -h $PGHOST -p $PGPORT -U $PGUSER"
$P -d postgres -c "drop database if exists $DB with (force)" -c "create database $DB"
sed "s/current_database_placeholder/$DB/" "$HERE/stub_supabase.sql" | $P -d "$DB" -v ON_ERROR_STOP=1 >/dev/null
for f in "$SB"/migrations/*.sql; do
  echo ">> migration $(basename "$f")"
  $P -d "$DB" -v ON_ERROR_STOP=1 -f "$f" >/dev/null
done
total=0; failed=0; files_failed=0
for f in "$SB"/tests/database/*.sql; do
  out=$(PGOPTIONS="-c search_path=public,extensions" psql -X -q -t -A -h $PGHOST -p $PGPORT -U $PGUSER -d "$DB" -v ON_ERROR_STOP=0 -f "$f" 2>&1 || true)
  n_ok=$(grep -cE '^ok ' <<<"$out" || true); n_nok=$(grep -cE '^not ok ' <<<"$out" || true)
  n_err=$(grep -cE 'ERROR:|FATAL:' <<<"$out" || true)
  plan=$(grep -E '^1\.\.[0-9]+' <<<"$out" | head -1 || true)
  echo "== $(basename "$f"): ok=$n_ok not_ok=$n_nok sql_errors=$n_err plan=${plan:-none}"
  if [ "$n_nok" -gt 0 ] || [ "$n_err" -gt 0 ] || [ -z "$plan" ] || [ "$plan" != "1..$((n_ok+n_nok))" ]; then
    files_failed=$((files_failed+1)); grep -E '^not ok|^# |ERROR|DETAIL|CONTEXT|HINT|LINE' <<<"$out" | head -60
  fi
  total=$((total+n_ok+n_nok)); failed=$((failed+n_nok))
done
echo "TOTAL assertions=$total failed=$failed files_failed=$files_failed"
[ "$files_failed" -eq 0 ]
