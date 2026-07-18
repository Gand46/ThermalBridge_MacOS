#!/bin/bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.cargo/bin:/usr/bin:/bin:/usr/sbin:/sbin"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

OUT="$HOME/Desktop/ThermalBridge_Temperatura_$(date +%Y%m%d_%H%M%S).txt"
find_helper() {
  for candidate in \
    "$ROOT_DIR/dist/ThermalBridge.app/Contents/Helpers/TBTemperatureSensor" \
    "$HOME/Applications/ThermalBridge.app/Contents/Helpers/TBTemperatureSensor" \
    "/Applications/ThermalBridge.app/Contents/Helpers/TBTemperatureSensor"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

{
  echo "ThermalBridge v0.7.0 RC3.5 - diagnóstico térmico MacThermal-compatible"
  date
  sw_vers
  uname -a
  echo

  HELPER="$(find_helper || true)"
  echo "Sensor máximo integrado: ${HELPER:-NO ENCONTRADO}"
  if [[ -n "$HELPER" ]]; then
    echo
    echo "Autoprueba de clasificación:"
    "$HELPER" --self-test 2>&1 || true

    echo
    echo "Catálogo CPU/GPU detectado (TCMb debe aparecer como CPU cuando exista):"
    SENSOR_LIST="$($HELPER --list-sensors 2>&1 || true)"
    printf '%s\n' "$SENSOR_LIST"
    if grep -q '^CPU TCMb ' <<<"$SENSOR_LIST"; then
      echo "VALIDACIÓN TCMb: incluido correctamente en CPU."
    elif grep -q 'TCMb' <<<"$SENSOR_LIST"; then
      echo "ADVERTENCIA TCMb: detectado, pero no quedó clasificado como CPU."
    else
      echo "INFO TCMb: AppleSMC no publicó esta clave en esta ejecución."
    fi

    echo
    echo "Tres muestras SMC (máximo individual y promedio):"
    "$HELPER" --samples 3 --interval 1000 2>&1 || true
  fi

  echo
  echo "macmon opcional para potencia/uso:"
  ls -l /opt/homebrew/bin/macmon /usr/local/bin/macmon "$HOME/.cargo/bin/macmon" 2>&1 || true
  if command -v macmon >/dev/null 2>&1; then
    echo "macmon: $(command -v macmon)"
    macmon --version 2>&1 || true
    echo "Muestra de potencia/uso y promedio de respaldo:"
    macmon pipe --samples 1 --interval 1000 2>&1 || true
  else
    echo "macmon no está instalado; esto no impide leer los máximos SMC."
  fi

  echo
  echo "Estado térmico del sistema:"
  pmset -g therm 2>&1 || true
} >"$OUT"

open -R "$OUT"
echo "Informe creado en: $OUT"
read -r -p "Pulsa Enter para cerrar."
