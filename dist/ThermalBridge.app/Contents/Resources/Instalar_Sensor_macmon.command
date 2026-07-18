#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.cargo/bin:/usr/bin:/bin:/usr/sbin:/sbin"

echo "================================================"
echo " ThermalBridge - macmon opcional (potencia y uso)"
echo "================================================"
echo

find_macmon() {
  for candidate in /opt/homebrew/bin/macmon /usr/local/bin/macmon "$HOME/.cargo/bin/macmon"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  command -v macmon 2>/dev/null || true
}

MACMON="$(find_macmon)"
if [[ -z "$MACMON" ]]; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "ERROR: Homebrew no está instalado."
    echo "Instala Homebrew desde https://brew.sh y vuelve a ejecutar este archivo."
    echo
    read -r -p "Pulsa Enter para cerrar."
    exit 1
  fi

  echo "Instalando macmon mediante Homebrew..."
  brew install macmon
  MACMON="$(find_macmon)"
fi

if [[ -z "$MACMON" || ! -x "$MACMON" ]]; then
  echo "ERROR: macmon no quedó disponible después de la instalación."
  read -r -p "Pulsa Enter para cerrar."
  exit 1
fi

echo
echo "Sensor encontrado: $MACMON"
echo "Probando una lectura CPU/GPU..."
TMP_FILE="$(mktemp -t thermalbridge_macmon)"
if "$MACMON" pipe --samples 1 --interval 1000 >"$TMP_FILE" 2>&1; then
  cat "$TMP_FILE"
  echo
  echo "macmon instalado y operativo para potencia/uso. El control por temperatura máxima usa el helper integrado."
  echo "Regresa a ThermalBridge y pulsa 'Reintentar sensor'."
else
  cat "$TMP_FILE"
  echo
  echo "ERROR: macmon se instaló, pero la prueba no produjo una lectura válida."
  rm -f "$TMP_FILE"
  read -r -p "Pulsa Enter para cerrar."
  exit 1
fi
rm -f "$TMP_FILE"

echo
read -r -p "Pulsa Enter para cerrar."
