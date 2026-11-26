#!/bin/bash
# Junta, en el mismo orden que cargar_todo.sh / docs/instalar-base-de-datos.md, todas las migraciones y datos en
# supabase/base_completa.sql: un solo archivo para instalar una base NUEVA desde cero (no para una base que ya existe).
cd "$(dirname "$0")/../supabase"
archivos=$(grep -o 'migrations/[^ ;]*\.sql\|seed/[^ ;]*\.sql\|datos/[^ ;]*\.sql' tests/cargar_todo.sh)
{
  echo "-- ====================================================================="
  echo "-- base_completa.sql — GENERADO por scripts/juntar_base.sh; no editar a mano."
  echo "-- Instala la base completa en un proyecto de Supabase NUEVO (vacío), en un solo paso."
  echo "-- En la base que ya está en uso NO se corre: ahí se siguen corriendo solo las migraciones nuevas."
  echo "-- Contiene, en orden: $(echo $archivos | wc -w) archivos."
  echo "-- ====================================================================="
  for f in $archivos; do
    echo; echo "-- >>>>>>>>>> $f"; cat "$f"
  done
} > base_completa.sql
echo "supabase/base_completa.sql: $(wc -l < base_completa.sql) líneas, $(echo $archivos | wc -w) archivos"
