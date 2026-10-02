#!/bin/bash
# Готовая сборка для GitHub Releases: dist/goblin-drag-macos.zip
set -euo pipefail

cd "$(dirname "$0")"
NAME="GOBL(in) Drag & Taskbar"
STAGE="dist/stage/${NAME}"
ZIP="dist/goblin-drag-macos.zip"

./build.sh universal

rm -rf dist
mkdir -p "${STAGE}"
ditto "${NAME}.app" "${STAGE}/${NAME}.app"

ditto -c -k --norsrc --noextattr --keepParent "${STAGE}" "${ZIP}"
rm -rf dist/stage
echo "$(pwd)/${ZIP}"
