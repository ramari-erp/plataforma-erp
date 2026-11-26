#!/bin/bash
# Corre todas las pruebas de la página (Playwright con api falsa). Uso: tests/navegador/correr.sh [prueba_x.js ...]
# Capturas de pantalla en $SALIDA (por omisión, la carpeta temporal).
cd "$(dirname "$0")"
export NODE_PATH=${NODE_PATH:-$(npm root -g)}
fallas=0
for f in ${@:-prueba*.js}; do
  salida=$(timeout 180 node "$f" 2>&1); codigo=$?
  if [ $codigo -ne 0 ] || echo "$salida" | grep -q "errores: \[[^]]" || echo "$salida" | grep -q "scroll[^:]*: SÍ"; then
    echo "FALLA  $f"; echo "$salida" | grep -i "error\|SÍ\|exceeded" | head -5 | sed 's/^/       /'; fallas=$((fallas + 1))
  else
    echo "bien   $f"
  fi
done
echo "Pruebas con falla: $fallas"
[ $fallas -eq 0 ]
