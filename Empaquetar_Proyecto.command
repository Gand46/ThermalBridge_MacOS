#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
README_FILE="$ROOT_DIR/README.md"
NO_PAUSE=false

if [[ "${1:-}" == "--no-pause" ]]; then
  NO_PAUSE=true
elif [[ $# -gt 0 ]]; then
  echo "Uso: Empaquetar_Proyecto.command [--no-pause]" >&2
  exit 64
fi

if [[ ! -f "$INFO_PLIST" || ! -f "$README_FILE" ]]; then
  echo "ERROR: faltan Resources/Info.plist o README.md." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
RELEASE_TITLE="$(sed -n '1s/^# ThermalBridge Auto //p' "$README_FILE")"
if [[ -z "$RELEASE_TITLE" || "$RELEASE_TITLE" != "$VERSION "* ]]; then
  echo "ERROR: el título de README.md no coincide con la versión $VERSION." >&2
  exit 1
fi

RELEASE_SLUG="$(printf '%s' "$RELEASE_TITLE" | tr ' ' '-' | tr -cd '[:alnum:]._-')"
PACKAGE_NAME="ThermalBridge_v${RELEASE_SLUG}-build${BUILD}-project"
RELEASE_DIR="$ROOT_DIR/releases"
ARCHIVE_PATH="$RELEASE_DIR/$PACKAGE_NAME.zip"
STAGING_ROOT="$(mktemp -d -t ThermalBridgeProjectPackage)"
STAGING_PROJECT="$STAGING_ROOT/$PACKAGE_NAME"
TEMP_ARCHIVE="$STAGING_ROOT/$PACKAGE_NAME.zip"

cleanup() {
  rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

# El ZIP representa el proyecto fuente reproducible. Las exclusiones se
# aplican antes de copiar para no tocar metadatos locales protegidos y evitar
# que un paquete anterior se incluya recursivamente.
mkdir -p "$STAGING_PROJECT"
/usr/bin/rsync -rltp \
  --exclude '.DS_Store' \
  --exclude '/.build/' \
  --exclude '/dist/' \
  --exclude '/releases/' \
  --exclude '/.git/' \
  --exclude '/.agents/' \
  --exclude '/.codex/' \
  --exclude '/validation_build.log' \
  --exclude '*.zip' \
  "$ROOT_DIR/" "$STAGING_PROJECT/"

mkdir -p "$RELEASE_DIR"
/usr/bin/ditto --norsrc --noextattr --noqtn --noacl \
  -c -k --keepParent "$STAGING_PROJECT" "$TEMP_ARCHIVE"
/usr/bin/unzip -tq "$TEMP_ARCHIVE" >/dev/null
ARCHIVE_LIST="$(/usr/bin/unzip -Z1 "$TEMP_ARCHIVE")"
if grep -Eq '(^|/)(\.build|dist|releases|\.git|\.agents|\.codex)(/|$)|(^|/)\._|(^|/)\.DS_Store$|(^|/)validation_build\.log$|\.zip$' <<<"$ARCHIVE_LIST"; then
  echo "ERROR: el ZIP contiene resultados o metadatos locales excluidos." >&2
  exit 1
fi
mv -f "$TEMP_ARCHIVE" "$ARCHIVE_PATH"

if $NO_PAUSE; then
  printf '%s\n' "$ARCHIVE_PATH"
  exit 0
fi

echo
echo "Proyecto empaquetado:"
echo "$ARCHIVE_PATH"
echo
open "$RELEASE_DIR"
echo "Pulsa Enter para cerrar."
read -r
