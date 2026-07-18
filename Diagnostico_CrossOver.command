#!/bin/bash
set -euo pipefail

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT="$HOME/Desktop/ThermalBridge_CrossOver_$STAMP.txt"
APP_SUPPORT="$HOME/Library/Application Support"

{
  echo "ThermalBridge 0.7.0 RC3.5 - Diagnóstico CrossOver"
  echo "Fecha: $(date)"
  echo "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  echo
  echo "=== Instalaciones detectables ==="
  find /Applications "$HOME/Applications" -maxdepth 1 -type d -iname '*CrossOver*.app' -print 2>/dev/null || true
  echo
  echo "=== Raíces y botellas detectables ==="
  found_root=0
  while IFS= read -r root; do
    [[ -n "$root" ]] || continue
    found_root=1
    echo "-- $root"
    find "$root" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null || true
  done < <(
    {
      printf '%s\n' "$APP_SUPPORT/CrossOver/Bottles"
      find "$APP_SUPPORT" -mindepth 1 -maxdepth 1 -type d -iname '*CrossOver*' -exec sh -c 'for d do printf "%s/Bottles\n" "$d"; done' sh {} + 2>/dev/null
    } | awk '!seen[$0]++' | while IFS= read -r candidate; do
      [[ -d "$candidate" ]] && printf '%s\n' "$candidate"
    done
  )
  if [[ "$found_root" -eq 0 ]]; then
    echo "No se encontraron carpetas de botellas de CrossOver."
  fi
  echo
  echo "=== Procesos CrossOver/Wine/EXE ==="
  echo "Formato: PID PPID usuario CPU memoria comando argumentos"
  ps -ww -axo pid=,ppid=,user=,%cpu=,%mem=,comm=,args= | grep -Ei 'CrossOver|wine|wineserver|cxstart|\.exe([[:space:]]|$)' | grep -v 'grep -E' || true
  echo
  echo "=== Procesos cuyo nombre macOS oculta detrás de Wine ==="
  ps -ww -axo pid=,ppid=,comm=,args= | awk 'BEGIN{IGNORECASE=1} /wine64-preloader|wine-preloader|cxstart/ {print}' || true
  echo
  echo "=== Árboles completos descendientes de CrossOver/Wine ==="
  echo "Incluye hosts con nombre neutro aunque no publiquen .exe en argv."
  ps -ww -axo pid=,ppid=,user=,%cpu=,%mem=,comm=,args= | awk '
    {
      line[NR] = $0
      pid[NR] = $1
      ppid[NR] = $2
      lower = tolower($0)
      if (lower ~ /crossover|wine|wineserver|cxstart|\.exe([[:space:]]|$)/) {
        selected[$1] = 1
      }
    }
    END {
      changed = 1
      while (changed) {
        changed = 0
        for (index = 1; index <= NR; index++) {
          if (!selected[pid[index]] && selected[ppid[index]]) {
            selected[pid[index]] = 1
            changed = 1
          }
        }
      }
      for (index = 1; index <= NR; index++) {
        if (selected[pid[index]]) print line[index]
      }
    }
  ' || true
  echo
  echo "=== Estabilidad durante 8 segundos ==="
  for sample in 1 2 3 4 5 6 7 8; do
    echo "-- muestra $sample $(date +%H:%M:%S)"
    ps -ww -axo pid=,ppid=,comm=,args= | grep -Ei 'CrossOver|wine|wineserver|cxstart|\.exe([[:space:]]|$)' | grep -v 'grep -E' || true
    sleep 1
  done
  echo
  echo "NOTA: la sección de procesos puede incluir rutas y argumentos de las aplicaciones abiertas."
} > "$OUTPUT"

open -R "$OUTPUT"
echo "Informe creado en:"
echo "$OUTPUT"
read -r -p "Presiona Enter para cerrar..." _
