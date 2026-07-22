#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

sha_check() {
  local manifest="$1"
  [[ -f "$manifest" ]] || fail "falta $manifest"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -c "$manifest"
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "$manifest"
  else
    fail "no se encontró shasum ni sha256sum"
  fi
}

printf '[1/7] Verificando versión y estructura fuente...\n'
[[ -f Resources/Info.plist ]] || fail "falta Resources/Info.plist"
[[ -f Sources/AutomaticThermalView.swift ]] || fail "falta AutomaticThermalView"
[[ -f Sources/ThermalControlLogic.swift ]] || fail "falta ThermalControlLogic"
[[ -f Sources/B1PredictiveThermalGovernor.swift ]] || fail "falta B1PredictiveThermalGovernor"
[[ -f Sources/ProcessStore.swift ]] || fail "falta ProcessStore"
[[ -f build_app.sh ]] || fail "falta build_app.sh"
[[ -f Validar.command ]] || fail "falta Validar.command"
[[ -f Prevalidar.command ]] || fail "falta Prevalidar.command"
[[ ! -e LegacyUI ]] || fail "LegacyUI no debe estar activo en la candidata actual"
[[ ! -e RC3_FROZEN_SHA256.txt ]] || fail "reapareció el manifiesto RC3 obsoleto"

grep -q '<string>0.7.0</string>' Resources/Info.plist || fail "CFBundleShortVersionString inesperado"
grep -q '<string>40</string>' Resources/Info.plist || fail "CFBundleVersion debe ser 40"
grep -q 'ThermalBridge Auto 0.7.0 RC3.13' README.md || fail "README no declara RC3.13"
grep -q 'VALIDACIÓN COMPLETADA: ThermalBridge 0.7.0 RC3.13 (40)' README.md || fail "README no documenta la validación RC3.13"

printf '[2/7] Verificando manifiestos congelados...\n'
sha_check BASELINE_BETA6_SHA256.txt
sha_check RC313_FROZEN_SHA256.txt

printf '[3/7] Verificando sintaxis Bash portable...\n'
for script in \
  build_app.sh \
  Validar.command \
  Prevalidar.command \
  Construir.command \
  Diagnostico_CrossOver.command \
  Diagnostico_Temperatura.command \
  Diagnostico_GPU.command \
  Instalar_en_Aplicaciones.command \
  Instalar_Sensor_macmon.command \
  Empaquetar_Proyecto.command; do
  bash -n "$script"
done

printf '[4/7] Verificando que no se versionen artefactos generados...\n'
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  TRACKED_ARTIFACTS="$(git ls-files .build dist releases validation_build.log '*.zip' || true)"
  if [[ -n "$TRACKED_ARTIFACTS" ]]; then
    printf '%s\n' "$TRACKED_ARTIFACTS"
    fail "hay artefactos generados versionados"
  fi
fi

printf '[5/7] Auditando exclusiones funcionales de la línea estable...\n'
if grep -REq 'automaticQoSFirstEnabled|qosMaintenanceActive|QoSLaunchSessionMatcher' Sources Tests; then
  fail "reapareció lógica QoS-first de Beta 7"
fi
if grep -REq 'GameModeController|gamepolicyctl|game-mode[[:space:]]+set' Sources; then
  fail "reapareció integración ejecutable de Game Mode"
fi
if grep -q 'TabView' Sources/AutomaticThermalView.swift; then
  fail "AutomaticThermalView no debe usar pestañas"
fi
if grep -q 'case disabled' Sources/MacProcessPolicy.swift; then
  fail "MacLaunchQoSClamp no debe incorporar opción desactivada"
fi

printf '[6/7] Verificando anclas de seguridad y privacidad...\n'
grep -q 'ProcessIdentity' Sources/Models.swift || fail "falta identidad PID+startID"
grep -q 'restoreAll' Sources/AutomaticThermalSupport.swift Sources/ProcessStore.swift || fail "falta restauración global"
grep -q 'SessionTelemetryWriter' Sources/SessionTelemetry.swift || fail "falta telemetría de sesión"
[[ -x Tools/Analizar_Telemetria_B1.py ]] || fail "falta analizador B1 ejecutable"
grep -q 'B1PredictiveThermalGovernor' Sources/B1PredictiveThermalGovernor.swift || fail "falta gobernador predictivo B1"
grep -q 'privacy' README.md SECURITY.md 2>/dev/null || true
! grep -REq 'screenshot|captura de pantalla' Sources || fail "no debe incorporarse captura de pantalla en fuentes"

printf '[7/7] Prevalidación completada.\n'
printf 'PREVALIDACIÓN COMPLETADA: ThermalBridge 0.7.0 RC3.13 (40)\n'
printf 'Nota: build nativo, firma, sensores y CrossOver real siguen pendientes en macOS Apple Silicon.\n'
