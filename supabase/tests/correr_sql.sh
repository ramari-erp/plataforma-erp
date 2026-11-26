#!/bin/bash
# Corre todas las pruebas SQL, cada una sobre una base recién cargada (cargar_todo.sh), y compara cuántos
# errores da contra los esperados (los errores esperados son los casos que la base DEBE rechazar).
D=${PGTEST:-/var/lib/postgresql/pgtest}; P="psql -h $D -p 5499 -U postgres -d t"
cd "$(dirname "$0")/../.."
declare -A esperados=([test_ordenes]=1 [test_pesada]=1 [test_contratos]=1 [test_planta]=2 [test_folios]=2 [test_formulas]=3
                      [test_ventas]=2 [test_cobranza]=5 [test_permisos]=2
                      [test_materias]=3 [test_pesadas_notas]=1)
declare -A antes=([test_permisos]=test_cobranza)   # pruebas que necesitan los datos de otra
fallas=0
for f in supabase/tests/test_*.sql; do
  n=$(basename "$f" .sql)
  bash supabase/tests/cargar_todo.sh >/dev/null 2>&1 || { echo "FALLA  carga de la base"; exit 1; }
  [ -n "${antes[$n]}" ] && $P -f "supabase/tests/${antes[$n]}.sql" >/dev/null 2>&1
  errores=$($P -f "$f" 2>&1 | grep -c "ERROR")
  if [ "$errores" = "${esperados[$n]:-0}" ]; then echo "bien   $n ($errores errores esperados)"; else echo "FALLA  $n: $errores errores, se esperaban ${esperados[$n]:-0}"; fallas=$((fallas + 1)); fi
done
echo "Pruebas con falla: $fallas"
[ $fallas -eq 0 ]
