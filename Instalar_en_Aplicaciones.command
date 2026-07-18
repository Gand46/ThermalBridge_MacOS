#!/bin/bash
set -e
cd "$(dirname "$0")"
./build_app.sh
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/ThermalBridge.app"
cp -R "dist/ThermalBridge.app" "$HOME/Applications/ThermalBridge.app"
open "$HOME/Applications/ThermalBridge.app"
echo
echo "Instalada en: $HOME/Applications/ThermalBridge.app"
echo "Pulsa Enter para cerrar."
read -r
