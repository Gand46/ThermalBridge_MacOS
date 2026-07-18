#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
MIN_MACOS="14.0"
ARCH="arm64"
SWIFT_LANGUAGE_VERSION="5"
SWIFT_TARGET="${ARCH}-apple-macosx${MIN_MACOS}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: la validación nativa debe ejecutarse en macOS."
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "ERROR: faltan las Command Line Tools de Xcode."
  echo "Instálalas con: xcode-select --install"
  exit 1
fi

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SWIFTC="$(xcrun --sdk macosx --find swiftc)"
CLANG="$(xcrun --sdk macosx --find clang)"
LIPO="$(xcrun --find lipo)"
MODULE_CACHE="$(mktemp -d -t ThermalBridgeModuleCache)"
PROFILE_TEST_BINARY="$(mktemp -t ThermalBridgeProfileTests)"
THERMAL_TEST_BINARY="$(mktemp -t ThermalBridgeThermalTests)"
SENSOR_TEST_BINARY="$(mktemp -t ThermalBridgeSensorTests)"
MAC_POLICY_TEST_BINARY="$(mktemp -t ThermalBridgeMacPolicyTests)"
CROSSOVER_TEST_BINARY="$(mktemp -t ThermalBridgeCrossOverTests)"
OBSERVATION_TEST_BINARY="$(mktemp -t ThermalBridgeObservationTests)"
RESOURCE_TEST_BINARY="$(mktemp -t ThermalBridgeResourceTests)"
TELEMETRY_TEST_BINARY="$(mktemp -t ThermalBridgeTelemetryTests)"
DISPLAY_TEST_BINARY="$(mktemp -t ThermalBridgeDisplayTests)"
MAC_POLICY_PROBE_BINARY="$(mktemp -t ThermalBridgeMacPolicyProbe)"
RESOURCE_PROBE_BINARY="$(mktemp -t ThermalBridgeResourceProbe)"
IOREPORT_PROBE_BINARY="$(mktemp -t ThermalBridgeIOReportProbe)"
SENSOR_OUTPUT_PROBE_BINARY="$(mktemp -t ThermalBridgeSensorOutputProbe)"
SENSOR_STDERR_FILE="$(mktemp -t ThermalBridgeSensorStderr)"
ANALYZER_LOG="$(mktemp -t ThermalBridgeAnalyzer)"
BUILD_LOG="$ROOT_DIR/validation_build.log"

SWIFT_SOURCES=(
  "$ROOT_DIR/Sources/Models.swift"
  "$ROOT_DIR/Sources/ThermalControlLogic.swift"
  "$ROOT_DIR/Sources/MacProcessPolicy.swift"
  "$ROOT_DIR/Sources/MacMonTemperatureSensor.swift"
  "$ROOT_DIR/Sources/ProcessObservationCache.swift"
  "$ROOT_DIR/Sources/ProcessResourceMetrics.swift"
  "$ROOT_DIR/Sources/ProcessSampler.swift"
  "$ROOT_DIR/Sources/ProcessController.swift"
  "$ROOT_DIR/Sources/SystemMetricsSampler.swift"
  "$ROOT_DIR/Sources/CrossOverDiscovery.swift"
  "$ROOT_DIR/Sources/SessionTelemetry.swift"
  "$ROOT_DIR/Sources/DisplayRefreshLogic.swift"
  "$ROOT_DIR/Sources/MacDisplayIntegration.swift"
  "$ROOT_DIR/Sources/ProcessStore.swift"
  "$ROOT_DIR/Sources/AutomaticThermalSupport.swift"
  "$ROOT_DIR/Sources/AutomaticThermalView.swift"
  "$ROOT_DIR/Sources/MenuBarView.swift"
  "$ROOT_DIR/Sources/ThermalBridgeApp.swift"
)

rm -f "$BUILD_LOG"
touch "$BUILD_LOG"
exec > >(tee -a "$BUILD_LOG") 2>&1

cleanup() {
  rm -rf "$MODULE_CACHE"
  rm -f "$PROFILE_TEST_BINARY" "$THERMAL_TEST_BINARY" "$SENSOR_TEST_BINARY" "$MAC_POLICY_TEST_BINARY" "$CROSSOVER_TEST_BINARY" "$OBSERVATION_TEST_BINARY" "$RESOURCE_TEST_BINARY" "$TELEMETRY_TEST_BINARY" "$DISPLAY_TEST_BINARY" "$MAC_POLICY_PROBE_BINARY" "$RESOURCE_PROBE_BINARY" "$IOREPORT_PROBE_BINARY" "$SENSOR_OUTPUT_PROBE_BINARY" "$SENSOR_STDERR_FILE" "$ANALYZER_LOG"
}
trap cleanup EXIT
trap 'printf "\nERROR: la validación no terminó correctamente.\nRevisa: %s\n" "$BUILD_LOG" >&2' ERR

printf '\nHerramientas detectadas:\n'
printf '  Xcode/CLT: %s\n' "$(xcode-select -p 2>/dev/null || echo 'desconocido')"
printf '  SDK:       %s\n' "$SDK_PATH"
printf '  Swift:     %s\n' "$($SWIFTC --version | head -n 1)"
printf '  Lenguaje:  Swift %s\n' "$SWIFT_LANGUAGE_VERSION"
printf '  Objetivo:  %s\n\n' "$SWIFT_TARGET"

printf '[1/10] Verificando estructura limpia e integridad...\n'
[[ -f "$ROOT_DIR/Sources/AutomaticThermalView.swift" ]]
[[ -f "$ROOT_DIR/Sources/AutomaticThermalSupport.swift" ]]
[[ -f "$ROOT_DIR/Sources/ThermalControlLogic.swift" ]]
[[ -f "$ROOT_DIR/Sources/MacProcessPolicy.swift" ]]
[[ -f "$ROOT_DIR/Tests/MacProcessPolicyTests.swift" ]]
[[ -f "$ROOT_DIR/Tests/MacPolicyProbe.c" ]]
[[ -f "$ROOT_DIR/Tests/CrossOverDetectionTests.swift" ]]
[[ -f "$ROOT_DIR/Tests/ProcessObservationCacheTests.swift" ]]
[[ -f "$ROOT_DIR/Sources/ProcessObservationCache.swift" ]]
[[ -f "$ROOT_DIR/Sources/ProcessResourceMetrics.swift" ]]
[[ -f "$ROOT_DIR/Tests/ProcessResourceMetricsTests.swift" ]]
[[ -f "$ROOT_DIR/Tests/ProcessResourceProbe.c" ]]
[[ -f "$ROOT_DIR/Sources/SessionTelemetry.swift" ]]
[[ -f "$ROOT_DIR/Tests/SessionTelemetryTests.swift" ]]
[[ -f "$ROOT_DIR/Sources/DisplayRefreshLogic.swift" ]]
[[ -f "$ROOT_DIR/Sources/MacDisplayIntegration.swift" ]]
[[ -f "$ROOT_DIR/Sources/TBDisplayGuardian.swift" ]]
[[ -f "$ROOT_DIR/Tests/DisplayRefreshLogicTests.swift" ]]
[[ -f "$ROOT_DIR/Tests/IOReportCapabilityProbe.c" ]]
[[ -f "$ROOT_DIR/BASELINE_BETA6_SHA256.txt" ]]
[[ -f "$ROOT_DIR/RC39_FROZEN_SHA256.txt" ]]
[[ -f "$ROOT_DIR/Tests/SensorOutputProbe.swift" ]]
[[ -f "$ROOT_DIR/Sources/MacMonTemperatureSensor.swift" ]]
[[ -f "$ROOT_DIR/Sources/TBTemperatureSensor.c" ]]
[[ -f "$ROOT_DIR/Instalar_Sensor_macmon.command" ]]
[[ -f "$ROOT_DIR/Empaquetar_Proyecto.command" ]]
[[ -f "$ROOT_DIR/Prevalidar.command" ]]
[[ ! -e "$ROOT_DIR/LegacyUI" ]]
[[ ! -e "$ROOT_DIR/RC3_FROZEN_SHA256.txt" ]]
[[ ! -e "$ROOT_DIR/PROTOCOLO_AB_BETA8.md" ]]
[[ ! -e "$ROOT_DIR/PROTOCOLO_VALIDACION_BETA9.md" ]]
[[ ! -e "$ROOT_DIR/PROTOCOLO_VALIDACION_BETA10.md" ]]
[[ ! -e "$ROOT_DIR/PROTOCOLO_VALIDACION_BETA11.md" ]]
! find "$ROOT_DIR/Sources" -maxdepth 1 -name 'SimpleCrossOver*.swift' | grep -q .
! grep -q 'TabView' "$ROOT_DIR/Sources/AutomaticThermalView.swift"
! grep -q 'CrossOverPreset' "$ROOT_DIR/Sources/AutomaticThermalView.swift"
grep -q 'cpuTargetCelsius' "$ROOT_DIR/Sources/AutomaticThermalView.swift"
grep -q 'gpuTargetCelsius' "$ROOT_DIR/Sources/AutomaticThermalView.swift"
grep -q 'CPU máxima' "$ROOT_DIR/Sources/AutomaticThermalView.swift"
grep -q 'GPU máxima' "$ROOT_DIR/Sources/AutomaticThermalView.swift"
grep -q 'evaluateAutomaticThermalMode' "$ROOT_DIR/Sources/ProcessStore.swift"
printf '  Verificando hashes y ausencia de la ruta QoS-first rechazada...\n'
(cd "$ROOT_DIR" && shasum -a 256 -c BASELINE_BETA6_SHA256.txt)
printf '  Verificando congelación completa de las fuentes RC3.9...\n'
(cd "$ROOT_DIR" && shasum -a 256 -c RC39_FROZEN_SHA256.txt)
if grep -REq 'automaticQoSFirstEnabled|qosMaintenanceActive|QoSLaunchSessionMatcher' \
    "$ROOT_DIR/Sources" "$ROOT_DIR/Tests"; then
  echo "ERROR: reapareció lógica QoS-first de Beta 7 en la línea estable."
  exit 1
fi

printf '[2/10] Comprobando tipos Swift de la aplicación completa...\n'
env -u MACOSX_DEPLOYMENT_TARGET "$SWIFTC" \
  -typecheck \
  -parse-as-library \
  -swift-version "$SWIFT_LANGUAGE_VERSION" \
  -target "$SWIFT_TARGET" \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  -import-objc-header "$ROOT_DIR/Sources/ProcessBridge.h" \
  "${SWIFT_SOURCES[@]}"

env -u MACOSX_DEPLOYMENT_TARGET "$SWIFTC" \
  -typecheck \
  -parse-as-library \
  -swift-version "$SWIFT_LANGUAGE_VERSION" \
  -target "$SWIFT_TARGET" \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT_DIR/Sources/TBDisplayGuardian.swift"

printf '[3/10] Auditando patrones SwiftUI problemáticos...\n'
STYLE_ISSUES="$(grep -nE 'foreground(Style|Color)\([^)]*\? *\.[A-Za-z0-9_]+ *: *\.[A-Za-z0-9_]+' "$ROOT_DIR/Sources/AutomaticThermalView.swift" "$ROOT_DIR/Sources/MenuBarView.swift" || true)"
if [[ -n "$STYLE_ISSUES" ]]; then
  echo "ERROR: se detectaron estilos abreviados ambiguos:"
  echo "$STYLE_ISSUES"
  exit 1
fi
DIRECT_FOREACH_ISSUES="$(grep -nE 'ForEach\(store\.' "$ROOT_DIR/Sources/AutomaticThermalView.swift" || true)"
if [[ -n "$DIRECT_FOREACH_ISSUES" ]]; then
  echo "ERROR: usa Array(...) y tipo explícito en ForEach con colecciones publicadas:"
  echo "$DIRECT_FOREACH_ISSUES"
  exit 1
fi

printf '[4/10] Ejecutando pruebas de lógica...\n'
env -u MACOSX_DEPLOYMENT_TARGET "$SWIFTC" \
  -parse-as-library \
  -swift-version "$SWIFT_LANGUAGE_VERSION" \
  -target "$SWIFT_TARGET" \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT_DIR/Sources/Models.swift" \
  "$ROOT_DIR/Tests/ProfileLogicTests.swift" \
  -framework Foundation \
  -o "$PROFILE_TEST_BINARY"
"$PROFILE_TEST_BINARY"

env -u MACOSX_DEPLOYMENT_TARGET "$SWIFTC" \
  -parse-as-library \
  -swift-version "$SWIFT_LANGUAGE_VERSION" \
  -target "$SWIFT_TARGET" \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT_DIR/Sources/Models.swift" \
  "$ROOT_DIR/Sources/ThermalControlLogic.swift" \
  "$ROOT_DIR/Tests/ThermalControlTests.swift" \
  -framework Foundation \
  -o "$THERMAL_TEST_BINARY"
"$THERMAL_TEST_BINARY"

env -u MACOSX_DEPLOYMENT_TARGET "$SWIFTC" \
  -parse-as-library \
  -swift-version "$SWIFT_LANGUAGE_VERSION" \
  -target "$SWIFT_TARGET" \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT_DIR/Sources/Models.swift" \
  "$ROOT_DIR/Sources/ThermalControlLogic.swift" \
  "$ROOT_DIR/Sources/MacMonTemperatureSensor.swift" \
  "$ROOT_DIR/Tests/SensorParsingTests.swift" \
  -framework Foundation \
  -o "$SENSOR_TEST_BINARY"
"$SENSOR_TEST_BINARY"

env -u MACOSX_DEPLOYMENT_TARGET "$SWIFTC" \
  -parse-as-library \
  -swift-version "$SWIFT_LANGUAGE_VERSION" \
  -target "$SWIFT_TARGET" \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT_DIR/Sources/Models.swift" \
  "$ROOT_DIR/Sources/MacProcessPolicy.swift" \
  "$ROOT_DIR/Tests/MacProcessPolicyTests.swift" \
  -framework Foundation \
  -o "$MAC_POLICY_TEST_BINARY"
"$MAC_POLICY_TEST_BINARY"

env -u MACOSX_DEPLOYMENT_TARGET "$SWIFTC" \
  -parse-as-library \
  -swift-version "$SWIFT_LANGUAGE_VERSION" \
  -target "$SWIFT_TARGET" \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT_DIR/Sources/Models.swift" \
  "$ROOT_DIR/Tests/CrossOverDetectionTests.swift" \
  -framework Foundation \
  -o "$CROSSOVER_TEST_BINARY"
"$CROSSOVER_TEST_BINARY"

env -u MACOSX_DEPLOYMENT_TARGET "$SWIFTC" \
  -parse-as-library \
  -swift-version "$SWIFT_LANGUAGE_VERSION" \
  -target "$SWIFT_TARGET" \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT_DIR/Sources/Models.swift" \
  "$ROOT_DIR/Sources/ProcessObservationCache.swift" \
  "$ROOT_DIR/Tests/ProcessObservationCacheTests.swift" \
  -framework Foundation \
  -o "$OBSERVATION_TEST_BINARY"
"$OBSERVATION_TEST_BINARY"

env -u MACOSX_DEPLOYMENT_TARGET "$SWIFTC" \
  -parse-as-library \
  -swift-version "$SWIFT_LANGUAGE_VERSION" \
  -target "$SWIFT_TARGET" \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT_DIR/Sources/Models.swift" \
  "$ROOT_DIR/Sources/ProcessResourceMetrics.swift" \
  "$ROOT_DIR/Tests/ProcessResourceMetricsTests.swift" \
  -framework Foundation \
  -o "$RESOURCE_TEST_BINARY"
"$RESOURCE_TEST_BINARY"

env -u MACOSX_DEPLOYMENT_TARGET "$SWIFTC" \
  -parse-as-library \
  -swift-version "$SWIFT_LANGUAGE_VERSION" \
  -target "$SWIFT_TARGET" \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT_DIR/Sources/Models.swift" \
  "$ROOT_DIR/Sources/ProcessResourceMetrics.swift" \
  "$ROOT_DIR/Sources/SessionTelemetry.swift" \
  "$ROOT_DIR/Tests/SessionTelemetryTests.swift" \
  -framework Foundation \
  -o "$TELEMETRY_TEST_BINARY"
"$TELEMETRY_TEST_BINARY"

env -u MACOSX_DEPLOYMENT_TARGET "$SWIFTC" \
  -parse-as-library \
  -swift-version "$SWIFT_LANGUAGE_VERSION" \
  -target "$SWIFT_TARGET" \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT_DIR/Sources/DisplayRefreshLogic.swift" \
  "$ROOT_DIR/Tests/DisplayRefreshLogicTests.swift" \
  -framework Foundation \
  -o "$DISPLAY_TEST_BINARY"
"$DISPLAY_TEST_BINARY"

env -u MACOSX_DEPLOYMENT_TARGET "$SWIFTC" \
  -parse-as-library \
  -swift-version "$SWIFT_LANGUAGE_VERSION" \
  -target "$SWIFT_TARGET" \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT_DIR/Tests/SensorOutputProbe.swift" \
  -framework Foundation \
  -o "$SENSOR_OUTPUT_PROBE_BINARY"

printf '[5/10] Analizando fuentes C, Info.plist y scripts...\n'
for source in ProcessBridge.c TBWatchdog.c TBCPULimiter.c TBLimiterGuardian.c TBTemperatureSensor.c; do
  "$CLANG" -fsyntax-only \
    -arch "$ARCH" \
    -isysroot "$SDK_PATH" \
    -mmacosx-version-min="$MIN_MACOS" \
    -Wall -Wextra \
    "$ROOT_DIR/Sources/$source"
done
printf '  Ejecutando analizador estático sobre la carga dinámica IOHID...\n'
for source in TBTemperatureSensor.c; do
  : > "$ANALYZER_LOG"
  if ! "$CLANG" --analyze \
    -Xanalyzer -analyzer-output=text \
    -arch "$ARCH" \
    -isysroot "$SDK_PATH" \
    -mmacosx-version-min="$MIN_MACOS" \
    -Wall -Wextra \
    "$ROOT_DIR/Sources/$source" \
    -o /dev/null 2>"$ANALYZER_LOG"; then
    echo "ERROR: el analizador estático no pudo completar $source:"
    sed 's/^/  /' "$ANALYZER_LOG"
    exit 1
  fi
  if grep -Eq '(^|: )(warning|error):' "$ANALYZER_LOG"; then
    echo "ERROR: el analizador estático detectó un problema en $source:"
    sed 's/^/  /' "$ANALYZER_LOG"
    exit 1
  fi
done
"$CLANG" \
  -arch "$ARCH" \
  -isysroot "$SDK_PATH" \
  -mmacosx-version-min="$MIN_MACOS" \
  -Wall -Wextra \
  "$ROOT_DIR/Tests/MacPolicyProbe.c" \
  -o "$MAC_POLICY_PROBE_BINARY"
printf '  Probando Darwin Background, clamp QoS y tiers opcionales...\n'
set +e
"$MAC_POLICY_PROBE_BINARY"
MAC_POLICY_STATUS=$?
set -e
case "$MAC_POLICY_STATUS" in
  0) printf '  PASS: políticas macOS disponibles o capacidades ausentes marcadas SKIP.\n' ;;
  2) printf '  DEGRADED: una política opcional no está disponible; continúa la validación.\n' ;;
  *) echo "ERROR: MacPolicyProbe detectó una aplicación sin restauración o un fallo real."; exit 1 ;;
esac
"$CLANG" \
  -arch "$ARCH" \
  -isysroot "$SDK_PATH" \
  -mmacosx-version-min="$MIN_MACOS" \
  -Wall -Wextra \
  "$ROOT_DIR/Tests/ProcessResourceProbe.c" \
  -lproc \
  -o "$RESOURCE_PROBE_BINARY"
printf '  Probando versión rusage y contadores efectivos...\n'
"$RESOURCE_PROBE_BINARY"
"$CLANG" \
  -arch "$ARCH" \
  -isysroot "$SDK_PATH" \
  -mmacosx-version-min="$MIN_MACOS" \
  -Wall -Wextra \
  "$ROOT_DIR/Sources/ProcessBridge.c" \
  "$ROOT_DIR/Tests/IOReportCapabilityProbe.c" \
  -lproc \
  -o "$IOREPORT_PROBE_BINARY"
printf '  Probando disponibilidad IOReport sin crear suscripción...\n'
"$IOREPORT_PROBE_BINARY"
plutil -lint "$ROOT_DIR/Resources/Info.plist"
bash -n "$ROOT_DIR/build_app.sh"
bash -n "$ROOT_DIR/Prevalidar.command"
bash -n "$ROOT_DIR/Construir.command"
bash -n "$ROOT_DIR/Instalar_en_Aplicaciones.command"
bash -n "$ROOT_DIR/Instalar_Sensor_macmon.command"
bash -n "$ROOT_DIR/Empaquetar_Proyecto.command"
bash -n "$ROOT_DIR/Diagnostico_Temperatura.command"
bash -n "$ROOT_DIR/Diagnostico_GPU.command"
bash -n "$ROOT_DIR/Diagnostico_CrossOver.command"

printf '[6/10] Verificando integración del sensor máximo...\n'
grep -q 'TBTemperatureSensor' "$ROOT_DIR/Sources/MacMonTemperatureSensor.swift"
grep -q 'cpu_temp_max' "$ROOT_DIR/Sources/MacMonTemperatureSensor.swift"
grep -q 'gpu_temp_max' "$ROOT_DIR/Sources/MacMonTemperatureSensor.swift"
grep -q 'cpuMaximumCelsius' "$ROOT_DIR/Sources/ThermalControlLogic.swift"
grep -q 'peakPreservingValue' "$ROOT_DIR/Sources/ThermalControlLogic.swift"
grep -q 'is_cpu_temperature_key' "$ROOT_DIR/Sources/TBTemperatureSensor.c"
grep -q 'is_gpu_temperature_key' "$ROOT_DIR/Sources/TBTemperatureSensor.c"
grep -q 'brew install macmon' "$ROOT_DIR/Instalar_Sensor_macmon.command"
grep -Fq "name[1] == 'C'" "$ROOT_DIR/Sources/TBTemperatureSensor.c"
grep -q 'TCMb' "$ROOT_DIR/Sources/TBTemperatureSensor.c"
grep -q 'pACC MTR Temp Sensor' "$ROOT_DIR/Sources/TBTemperatureSensor.c"
grep -q 'GPU MTR Temp Sensor' "$ROOT_DIR/Sources/TBTemperatureSensor.c"
grep -q 'setSchedulingPolicy' "$ROOT_DIR/Sources/ProcessController.swift"
grep -q 'tb_set_qos_tiers' "$ROOT_DIR/Sources/ProcessBridge.c"
grep -q 'TASK_OVERRIDE_QOS_POLICY' "$ROOT_DIR/Sources/ProcessBridge.c"
grep -q 'MacApplicationPolicyPlanner' "$ROOT_DIR/Sources/MacProcessPolicy.swift"
grep -q 'MacLaunchQoSClamp' "$ROOT_DIR/Sources/MacProcessPolicy.swift"
grep -q 'crossOverSelectableProcesses' "$ROOT_DIR/Sources/ProcessStore.swift"
grep -q 'captureAutomaticThermalExecutable' "$ROOT_DIR/Sources/AutomaticThermalSupport.swift"
grep -q 'Buscar .exe' "$ROOT_DIR/Sources/AutomaticThermalView.swift"
grep -q 'TB_PROCESS_COMMAND_MAX 4096' "$ROOT_DIR/Sources/ProcessBridge.h"
grep -q 'WINEPREFIX=' "$ROOT_DIR/Sources/ProcessBridge.c"
grep -q 'tb_has_crossover_ancestor' "$ROOT_DIR/Sources/ProcessBridge.c"
grep -q 'pid_buffer_bytes' "$ROOT_DIR/Sources/ProcessBridge.c"
grep -q 'ProcessObservationCache' "$ROOT_DIR/Sources/ProcessStore.swift"
grep -q 'processObservationGraceInterval' "$ROOT_DIR/Sources/ProcessStore.swift"
grep -q 'automaticThermalPreferredProcessID' "$ROOT_DIR/Sources/ProcessStore.swift"
grep -q 'automaticThermalPreferredExecutableNeedle' "$ROOT_DIR/Sources/ProcessStore.swift"
grep -q 'automaticThermalMissingSamples <= 5' "$ROOT_DIR/Sources/AutomaticThermalSupport.swift"
grep -q 'repairAutomaticThermalBottleIfNeeded' "$ROOT_DIR/Sources/AutomaticThermalSupport.swift"
grep -q 'strongExecutableMatches' "$ROOT_DIR/Sources/AutomaticThermalSupport.swift"
grep -q 'Olvidar botella' "$ROOT_DIR/Sources/AutomaticThermalView.swift"
grep -q 'testExactExecutableAllowsTemporarilyHiddenBottle' "$ROOT_DIR/Tests/ThermalControlTests.swift"
grep -q 'testUnambiguousStrongExecutableRecovery' "$ROOT_DIR/Tests/ThermalControlTests.swift"
grep -q 'testAmbiguousStrongExecutableRecoveryAcrossBottles' "$ROOT_DIR/Tests/ThermalControlTests.swift"
grep -q 'ProcessObservationCacheTests: OK' "$ROOT_DIR/Tests/ProcessObservationCacheTests.swift"
! grep -q 'onChange(of: selectedProcessID)' "$ROOT_DIR/Sources/AutomaticThermalView.swift"
grep -q 'JSONSerialization.jsonObject' "$ROOT_DIR/Tests/SensorOutputProbe.swift"
grep -q 'tb_set_darwin_background' "$ROOT_DIR/Sources/ProcessBridge.c"
grep -q 'tb_spawn_with_qos_clamp' "$ROOT_DIR/Sources/ProcessBridge.c"
grep -q 'posix_spawnattr_set_qos_clamp_np' "$ROOT_DIR/Sources/ProcessBridge.c"
grep -q 'launchCrossOverWithQoS' "$ROOT_DIR/Sources/AutomaticThermalSupport.swift"
grep -q 'recordCrossOverEfficientLaunch' "$ROOT_DIR/Sources/ProcessStore.swift"
grep -q 'freshAuxiliaryMetrics' "$ROOT_DIR/Sources/MacMonTemperatureSensor.swift"
grep -q 'Darwin Background para el juego solo en emergencia' "$ROOT_DIR/Sources/AutomaticThermalView.swift"

printf '[7/10] Verificando limitador, potencia predictiva y controles nativos...\n'
grep -q 'read_control_settings' "$ROOT_DIR/Sources/TBCPULimiter.c"
grep -q 'pulse-mode' "$ROOT_DIR/Sources/TBCPULimiter.c"
grep -q 'updateCPULimiter' "$ROOT_DIR/Sources/ProcessController.swift"
grep -q 'lastAutomaticThermalDecisionReadingDate' "$ROOT_DIR/Sources/AutomaticThermalSupport.swift"
grep -q 'actividad mínima alcanzada' "$ROOT_DIR/Sources/ThermalControlLogic.swift"
grep -q 'positiveErrorIntegral' "$ROOT_DIR/Sources/ThermalControlLogic.swift"
grep -q 'predictivePowerPressure' "$ROOT_DIR/Sources/ThermalControlLogic.swift"
grep -q 'testPowerAnticipatesThermalLimit' "$ROOT_DIR/Tests/ThermalControlTests.swift"
grep -q 'testInvalidPowerIsIgnored' "$ROOT_DIR/Tests/ThermalControlTests.swift"
grep -q 'testIntegralDetectsSustainedSmallExcess' "$ROOT_DIR/Tests/ThermalControlTests.swift"
grep -q 'automaticThermalEmergencyBackgroundSourceKey' "$ROOT_DIR/Sources/AutomaticThermalSupport.swift"
grep -q 'ActivityLimiterPulseMode' "$ROOT_DIR/Sources/ThermalControlLogic.swift"
grep -q 'AudioSafeLimiterTiming' "$ROOT_DIR/Sources/ThermalControlLogic.swift"
grep -q 'automaticAudioProtectionEnabled' "$ROOT_DIR/Sources/ProcessStore.swift"
grep -q 'Proteger continuidad de audio' "$ROOT_DIR/Sources/AutomaticThermalView.swift"
grep -q 'mach_wait_until' "$ROOT_DIR/Sources/TBCPULimiter.c"
grep -q 'signal_primary' "$ROOT_DIR/Sources/TBCPULimiter.c"
grep -q 'stop_us = 2000ULL' "$ROOT_DIR/Sources/TBCPULimiter.c"
grep -q 'previous_pulse_mode' "$ROOT_DIR/Sources/TBCPULimiter.c"
grep -q 'testAudioSafeLimiterAvoidsLongPauses' "$ROOT_DIR/Tests/ThermalControlTests.swift"
grep -q 'testAudioSafeLimiterPreservesRequestedRatio' "$ROOT_DIR/Tests/ThermalControlTests.swift"
grep -q 'host principal, pausas de hasta 2 ms' "$ROOT_DIR/Sources/AutomaticThermalSupport.swift"
grep -q 'SessionTelemetryWriter' "$ROOT_DIR/Sources/SessionTelemetry.swift"
grep -q 'recordDecision' "$ROOT_DIR/Sources/AutomaticThermalSupport.swift"
grep -q 'testBeta6GoldenRisingTrace' "$ROOT_DIR/Tests/ThermalControlTests.swift"
grep -q 'SessionTelemetryTests: OK' "$ROOT_DIR/Tests/SessionTelemetryTests.swift"
grep -q 'ProcessResourceMetricsTests: OK' "$ROOT_DIR/Tests/ProcessResourceMetricsTests.swift"
grep -Fq 'let observedPairs: [(EffectiveQoSClass, UInt64)]' "$ROOT_DIR/Sources/ProcessResourceMetrics.swift"
grep -q 'RUSAGE_INFO_V6' "$ROOT_DIR/Sources/ProcessBridge.c"
grep -q 'RUSAGE_INFO_V3' "$ROOT_DIR/Sources/ProcessBridge.c"
grep -q 'ri_energy_nj' "$ROOT_DIR/Sources/ProcessBridge.c"
grep -q 'ri_cpu_time_qos_maintenance' "$ROOT_DIR/Sources/ProcessBridge.c"
grep -q 'TBLimiterGuardian' "$ROOT_DIR/Sources/ProcessController.swift"
grep -q 'controlQueue.sync' "$ROOT_DIR/Sources/AutomaticThermalSupport.swift"
grep -q 'ProcessRestorationResolver' "$ROOT_DIR/Sources/Models.swift"
grep -q 'backgroundSnapshots' "$ROOT_DIR/Sources/ProcessStore.swift"
grep -q 'failedBackgroundRestorations' "$ROOT_DIR/Sources/ProcessStore.swift"
grep -q 'ProcessRestorationResolver' "$ROOT_DIR/Tests/ProfileLogicTests.swift"
grep -q 'dlopen' "$ROOT_DIR/Sources/TBTemperatureSensor.c"
grep -q 'dlsym' "$ROOT_DIR/Sources/TBTemperatureSensor.c"
grep -q 'DisplayRefreshPlanner' "$ROOT_DIR/Sources/DisplayRefreshLogic.swift"
grep -q 'DisplayRefreshController' "$ROOT_DIR/Sources/MacDisplayIntegration.swift"
grep -q 'CGDisplaySetDisplayMode' "$ROOT_DIR/Sources/MacDisplayIntegration.swift"
grep -q 'TBDisplayGuardian' "$ROOT_DIR/Sources/MacDisplayIntegration.swift"
grep -q 'guardianActive' "$ROOT_DIR/Sources/AutomaticThermalSupport.swift"
grep -q 'getppid' "$ROOT_DIR/Sources/TBDisplayGuardian.swift"
grep -q 'restoreDisplayRefreshSafety' "$ROOT_DIR/Sources/AutomaticThermalSupport.swift"
grep -q 'automaticGPURefreshReductionEnabled' "$ROOT_DIR/Sources/AutomaticThermalView.swift"
grep -q 'tb_ioreport_capability' "$ROOT_DIR/Sources/ProcessBridge.c"
grep -q 'IOReportCreateSamplesDelta' "$ROOT_DIR/Sources/ProcessBridge.c"
grep -q 'IOReportCapabilityProbe: PASS' "$ROOT_DIR/Tests/IOReportCapabilityProbe.c"
grep -q 'DisplayRefreshLogicTests: OK' "$ROOT_DIR/Tests/DisplayRefreshLogicTests.swift"
if grep -REq 'GameModeController|gamepolicyctl|game-mode[[:space:]]+set' "$ROOT_DIR/Sources"; then
  echo "ERROR: reapareció la integración Game Mode retirada en RC3.9."
  exit 1
fi

printf '[8/10] Compilando la aplicación completa...\n'
"$ROOT_DIR/build_app.sh"

printf '  Probando temporización de audio protegido...\n'
"$ROOT_DIR/dist/ThermalBridge.app/Contents/Helpers/TBCPULimiter" --self-test
printf '  Probando identidad del guardián del limitador...\n'
"$ROOT_DIR/dist/ThermalBridge.app/Contents/Helpers/TBLimiterGuardian" --self-test
printf '  Probando selección del modo original del guardián de pantalla...\n'
"$ROOT_DIR/dist/ThermalBridge.app/Contents/Helpers/TBDisplayGuardian" --self-test

printf '[9/10] Verificando versión, binarios, recursos y firma...\n'
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT_DIR/Resources/Info.plist")"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ROOT_DIR/Resources/Info.plist")"
[[ "$VERSION" == "0.7.0" && "$BUILD" == "33" ]]
[[ "$BUNDLE_IDENTIFIER" == "com.germangomez.thermalbridge" ]]
[[ -x "$ROOT_DIR/dist/ThermalBridge.app/Contents/MacOS/ThermalBridge" ]]
[[ -x "$ROOT_DIR/dist/ThermalBridge.app/Contents/Helpers/TBWatchdog" ]]
[[ -x "$ROOT_DIR/dist/ThermalBridge.app/Contents/Helpers/TBCPULimiter" ]]
[[ -x "$ROOT_DIR/dist/ThermalBridge.app/Contents/Helpers/TBLimiterGuardian" ]]
[[ -x "$ROOT_DIR/dist/ThermalBridge.app/Contents/Helpers/TBDisplayGuardian" ]]
[[ -x "$ROOT_DIR/dist/ThermalBridge.app/Contents/Helpers/TBTemperatureSensor" ]]
[[ -x "$ROOT_DIR/dist/ThermalBridge.app/Contents/Resources/Instalar_Sensor_macmon.command" ]]
RC_BINARIES=(
  "$ROOT_DIR/dist/ThermalBridge.app/Contents/MacOS/ThermalBridge"
  "$ROOT_DIR/dist/ThermalBridge.app/Contents/Helpers/TBWatchdog"
  "$ROOT_DIR/dist/ThermalBridge.app/Contents/Helpers/TBCPULimiter"
  "$ROOT_DIR/dist/ThermalBridge.app/Contents/Helpers/TBLimiterGuardian"
  "$ROOT_DIR/dist/ThermalBridge.app/Contents/Helpers/TBDisplayGuardian"
  "$ROOT_DIR/dist/ThermalBridge.app/Contents/Helpers/TBTemperatureSensor"
)
for binary in "${RC_BINARIES[@]}"; do
  BINARY_ARCHS="$("$LIPO" -archs "$binary")"
  [[ "$BINARY_ARCHS" == "arm64" ]]
  codesign --verify --strict "$binary"
  printf '  arm64 + firma OK: %s\n' "$(basename "$binary")"
done
codesign --verify --deep --strict "$ROOT_DIR/dist/ThermalBridge.app"
SIGNATURE_INFO="$(codesign -dv --verbose=4 "$ROOT_DIR/dist/ThermalBridge.app" 2>&1)"
grep -Fqx 'Identifier=com.germangomez.thermalbridge' <<<"$SIGNATURE_INFO"

printf '[10/10] Probando clasificación MacThermal y lectura máxima real...\n'
"$ROOT_DIR/dist/ThermalBridge.app/Contents/Helpers/TBTemperatureSensor" --self-test
SENSOR_LIST="$("$ROOT_DIR/dist/ThermalBridge.app/Contents/Helpers/TBTemperatureSensor" --list-sensors 2>&1 || true)"
if grep -q 'TCMb' <<<"$SENSOR_LIST"; then
  grep -q '^CPU TCMb ' <<<"$SENSOR_LIST"
  printf '  TCMb incluido correctamente en CPU.\n'
else
  printf '  TCMb no fue publicado por AppleSMC en esta muestra; autoprueba sintética correcta.\n'
fi
rm -f "$SENSOR_STDERR_FILE"
SENSOR_OUTPUT="$("$ROOT_DIR/dist/ThermalBridge.app/Contents/Helpers/TBTemperatureSensor" --samples 1 --interval 250 2>"$SENSOR_STDERR_FILE")"
if [[ -s "$SENSOR_STDERR_FILE" ]]; then
  sed 's/^/  /' "$SENSOR_STDERR_FILE"
fi
NON_EMPTY_JSON_LINES="$(printf '%s\n' "$SENSOR_OUTPUT" | awk 'NF { count += 1 } END { print count + 0 }')"
if [[ "$NON_EMPTY_JSON_LINES" -ne 1 ]]; then
  echo "ERROR: el sensor debía emitir exactamente un objeto JSON y produjo $NON_EMPTY_JSON_LINES líneas no vacías."
  printf 'Salida recibida:\n%s\n' "$SENSOR_OUTPUT"
  exit 1
fi
if ! printf '%s\n' "$SENSOR_OUTPUT" | "$SENSOR_OUTPUT_PROBE_BINARY"; then
  echo "ERROR: la muestra del sensor no superó JSONSerialization."
  printf 'Salida recibida:\n%s\n' "$SENSOR_OUTPUT"
  exit 1
fi
grep -q '"cpu_temp_max"' <<<"$SENSOR_OUTPUT"
grep -q '"gpu_temp_max"' <<<"$SENSOR_OUTPUT"
grep -q '"cpu_max_sensor"' <<<"$SENSOR_OUTPUT"
grep -q '"gpu_max_sensor"' <<<"$SENSOR_OUTPUT"
grep -q '"iohid_available"' <<<"$SENSOR_OUTPUT"
printf '  Muestra SMC validada: %s\n' "$SENSOR_OUTPUT"

printf '  Empaquetando el proyecto fuente validado...\n'
PROJECT_ARCHIVE="$("$ROOT_DIR/Empaquetar_Proyecto.command" --no-pause)"
[[ -f "$PROJECT_ARCHIVE" ]]
/usr/bin/unzip -tq "$PROJECT_ARCHIVE" >/dev/null
printf '  ZIP del proyecto: %s\n' "$PROJECT_ARCHIVE"

printf '\nVALIDACIÓN COMPLETADA: ThermalBridge %s RC3.9 (%s)\n' "$VERSION" "$BUILD"
printf 'Aplicación validada: %s\n' "$ROOT_DIR/dist/ThermalBridge.app"
