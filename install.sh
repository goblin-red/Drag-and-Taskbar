#!/bin/bash
# Установка GOBL(in) Drag: скачивает готовую сборку из GitHub Releases.
#   curl -fsSL https://raw.githubusercontent.com/goblin-red/two-finger-drag-macos/main/install.sh | bash
# Свой путь установки: GOBLIN_INSTALL_DIR=~/Apps; не открывать после установки: bash -s -- --no-open
set -euo pipefail

REPO="goblin-red/two-finger-drag-macos"
ASSET="goblin-drag-macos.zip"
NAME="GOBL(in) Drag"
URL="https://github.com/${REPO}/releases/latest/download/${ASSET}"

# Куда ставить: /Applications, а если туда нельзя писать — ~/Applications
DEST_ROOT="${GOBLIN_INSTALL_DIR:-/Applications}"
mkdir -p "${DEST_ROOT}" 2>/dev/null || true
if [ ! -w "${DEST_ROOT}" ]; then
    DEST_ROOT="${HOME}/Applications"
    mkdir -p "${DEST_ROOT}"
fi
# Приложение живёт в своей папке: рядом с ним оно хранит config.txt
DEST="${DEST_ROOT}/${NAME}"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "==> Downloading ${NAME} ..."
curl -fL --progress-bar "${URL}" -o "${TMP}/app.zip"
ditto -x -k "${TMP}/app.zip" "${TMP}/unpacked"

# Закрываем работающую копию и заменяем приложение, настройки не трогаем
killall TwoFingerDrag 2>/dev/null || true
mkdir -p "${DEST}"
rm -rf "${DEST}/${NAME}.app"
ditto "${TMP}/unpacked/${NAME}/${NAME}.app" "${DEST}/${NAME}.app"
xattr -dr com.apple.quarantine "${DEST}" 2>/dev/null || true

echo "==> Installed: ${DEST}"
echo "    Allow it once: System Settings -> Privacy & Security -> Accessibility -> ${NAME}"
if [ "${1:-}" != "--no-open" ]; then
    open "${DEST}/${NAME}.app"
fi
