#!/bin/bash
set -e
cd "$(dirname "$0")"
./build_app.sh
open "$(pwd)/dist"
echo
echo "Pulsa Enter para cerrar."
read -r
