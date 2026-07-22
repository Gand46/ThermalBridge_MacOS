#!/bin/bash
set -euo pipefail

APP_NAME="ThermalBridge"
MIN_MACOS="14.0"
ARCH="arm64"
SWIFT_LANGUAGE_VERSION="5"
SWIFT_TARGET="${ARCH}-apple-macosx${MIN_MACOS}"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
HELPERS_DIR="$CONTENTS_DIR/Helpers"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: este proyecto debe compilarse en macOS."
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "ERROR: faltan las herramientas de Xcode."
  echo "Instálalas con: xcode-select --install"
  exit 1
fi

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SWIFTC="$(xcrun --sdk macosx --find swiftc)"
CLANG="$(xcrun --sdk macosx --find clang)"

rm -rf "$BUILD_DIR" "$APP_DIR"
mkdir -p "$BUILD_DIR" "$MACOS_DIR" "$RESOURCES_DIR" "$HELPERS_DIR"

COMMON_C_FLAGS=(
  -arch "$ARCH"
  -isysroot "$SDK_PATH"
  -mmacosx-version-min="$MIN_MACOS"
  -O2
  -Wall
  -Wextra
)

SWIFT_SOURCES=(
  "$ROOT_DIR/Sources/Models.swift"
  "$ROOT_DIR/Sources/ThermalControlLogic.swift"
  "$ROOT_DIR/Sources/B1PredictiveThermalGovernor.swift"
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

for source in "${SWIFT_SOURCES[@]}"; do
  if [[ ! -f "$source" ]]; then
    echo "ERROR: falta el archivo Swift: $source"
    exit 1
  fi
done

echo "[1/9] Compilando puente de procesos..."
"$CLANG" "${COMMON_C_FLAGS[@]}" \
  -c "$ROOT_DIR/Sources/ProcessBridge.c" \
  -o "$BUILD_DIR/ProcessBridge.o"

echo "[2/9] Compilando watchdog de suspensión..."
"$CLANG" "${COMMON_C_FLAGS[@]}" \
  "$ROOT_DIR/Sources/TBWatchdog.c" \
  -lproc \
  -o "$HELPERS_DIR/TBWatchdog"
chmod +x "$HELPERS_DIR/TBWatchdog"

echo "[3/9] Compilando controlador de actividad por árbol..."
"$CLANG" "${COMMON_C_FLAGS[@]}" \
  "$ROOT_DIR/Sources/TBCPULimiter.c" \
  -lproc \
  -o "$HELPERS_DIR/TBCPULimiter"
chmod +x "$HELPERS_DIR/TBCPULimiter"

echo "[4/9] Compilando guardián independiente del limitador..."
"$CLANG" "${COMMON_C_FLAGS[@]}" \
  "$ROOT_DIR/Sources/TBLimiterGuardian.c" \
  -lproc \
  -o "$HELPERS_DIR/TBLimiterGuardian"
chmod +x "$HELPERS_DIR/TBLimiterGuardian"

echo "[5/9] Compilando guardián independiente de pantalla..."
env -u MACOSX_DEPLOYMENT_TARGET "$SWIFTC" \
  -parse-as-library \
  -swift-version "$SWIFT_LANGUAGE_VERSION" \
  -O \
  -target "$SWIFT_TARGET" \
  -sdk "$SDK_PATH" \
  "$ROOT_DIR/Sources/TBDisplayGuardian.swift" \
  -framework CoreGraphics \
  -framework Foundation \
  -o "$HELPERS_DIR/TBDisplayGuardian"
chmod +x "$HELPERS_DIR/TBDisplayGuardian"

echo "[6/9] Compilando sensor térmico máximo por SMC..."
"$CLANG" "${COMMON_C_FLAGS[@]}" \
  "$ROOT_DIR/Sources/TBTemperatureSensor.c" \
  -framework IOKit \
  -framework CoreFoundation \
  -o "$HELPERS_DIR/TBTemperatureSensor"
chmod +x "$HELPERS_DIR/TBTemperatureSensor"
cp "$HELPERS_DIR/TBTemperatureSensor" "$BUILD_DIR/TBTemperatureSensor"


echo "[7/9] Compilando control térmico automático para CrossOver..."
env -u MACOSX_DEPLOYMENT_TARGET "$SWIFTC" \
  -parse-as-library \
  -swift-version "$SWIFT_LANGUAGE_VERSION" \
  -O \
  -whole-module-optimization \
  -target "$SWIFT_TARGET" \
  -sdk "$SDK_PATH" \
  -import-objc-header "$ROOT_DIR/Sources/ProcessBridge.h" \
  "${SWIFT_SOURCES[@]}" \
  "$BUILD_DIR/ProcessBridge.o" \
  -framework AppKit \
  -framework CoreGraphics \
  -framework Foundation \
  -framework ServiceManagement \
  -framework SwiftUI \
  -framework UniformTypeIdentifiers \
  -lproc \
  -o "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

echo "[8/9] Creando paquete .app..."
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Instalar_Sensor_macmon.command" "$RESOURCES_DIR/Instalar_Sensor_macmon.command"
chmod +x "$RESOURCES_DIR/Instalar_Sensor_macmon.command"
if command -v iconutil >/dev/null 2>&1; then
  iconutil -c icns "$ROOT_DIR/Resources/AppIcon.iconset" -o "$RESOURCES_DIR/AppIcon.icns"
fi
plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null

echo "[9/9] Firmando localmente..."
codesign --force --deep --sign - "$APP_DIR" >/dev/null

cat <<MSG

Compilación completada:
$APP_DIR

Para abrirla:
  open "$APP_DIR"

La primera apertura puede requerir clic derecho > Abrir porque la firma es local.
MSG
