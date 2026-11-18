#!/bin/bash
# Carga una base de prueba local en el MISMO orden que se ejecuta en Supabase.
D=${PGTEST:-/var/lib/postgresql/pgtest}; P="psql -h $D -p 5499 -U postgres -v ON_ERROR_STOP=1 -q"
cd "$(dirname "$0")/.."
$P -c "drop database if exists t" -c "create database t" || exit 1
for f in tests/supabase_stub.sql migrations/0001_base.sql migrations/0002_planta.sql seed/0001_catalogo_planta.sql migrations/0003_capacidades_planta.sql migrations/0004_pantallas_planta.sql migrations/0005_inventario_fisico.sql migrations/0006_ordenes_produccion.sql migrations/0007_contratos_granos.sql migrations/0008_orden_granja_destino.sql; do
  $P -d t -f "$f" >/dev/null || { echo "Falló: $f"; exit 1; }
done
