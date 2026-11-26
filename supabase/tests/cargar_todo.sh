#!/bin/bash
# Carga una base de prueba local en el MISMO orden que se ejecuta en Supabase.
D=${PGTEST:-/var/lib/postgresql/pgtest}; P="psql -h $D -p 5499 -U postgres -v ON_ERROR_STOP=1 -q"
cd "$(dirname "$0")/.."
$P -c "drop database if exists t" -c "create database t" || exit 1
for f in tests/supabase_stub.sql migrations/0001_base.sql migrations/0002_planta.sql seed/0001_catalogo_planta.sql migrations/0003_capacidades_planta.sql migrations/0004_pantallas_planta.sql migrations/0005_inventario_fisico.sql migrations/0006_ordenes_produccion.sql migrations/0007_contratos_granos.sql migrations/0008_orden_granja_destino.sql migrations/0009_orden_area.sql migrations/0010_pesada_real.sql migrations/0011_casetas_secciones.sql migrations/0012_superficie_granjas.sql datos/0001_casetas_tolvas.sql migrations/0013_materias_nuevas.sql migrations/0014_formulas_nuevas.sql datos/0002_formulas_maiz.sql migrations/0015_llegadas_pendientes.sql migrations/0016_folios_unicos.sql migrations/0017_pesadas_y_notas.sql migrations/0018_ventas.sql migrations/0019_berries_generales_cobranza.sql migrations/0020_flete_por_caja.sql migrations/0021_flete_descuenta.sql migrations/0022_destino_huevo.sql migrations/0023_sorgo_maiz_pagos.sql migrations/0024_pesada_unica_facturas.sql; do
  $P -d t -f "$f" >/dev/null || { echo "Falló: $f"; exit 1; }
done
