#!/bin/bash
set -u

STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="$HOME/Desktop/ThermalBridge_GPU_Diagnostico_$STAMP.txt"

{
  echo "ThermalBridge 0.7.0 RC3.5 - Diagnóstico GPU"
  echo "Fecha: $(date)"
  echo
  echo "=== macOS ==="
  sw_vers 2>&1
  echo
  echo "=== Hardware ==="
  /usr/sbin/system_profiler SPHardwareDataType SPDisplaysDataType 2>&1
  echo
  echo "=== IORegistry: AGXAccelerator ==="
  /usr/sbin/ioreg -r -c AGXAccelerator -l -w 0 2>&1
  echo
  echo "=== IORegistry: IOAccelerator ==="
  /usr/sbin/ioreg -r -c IOAccelerator -l -w 0 2>&1
  echo
  echo "=== powermetrics ayuda ==="
  /usr/bin/powermetrics -h 2>&1
} > "$OUT"

open -R "$OUT"
echo "Diagnóstico guardado en:"
echo "$OUT"
read -r -p "Presiona Enter para cerrar..." _
