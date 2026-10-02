#!/bin/bash
set -euo pipefail

# =============================================================================
#  GOBL(in) Drag — сборка .app
#
#  Режимы (аргумент №1):
#     ./build.sh              arm64+x86_64 — оба среза в одном бинарнике (lipo), ДЕФОЛТ
#     ./build.sh arm          arm64      — только Apple Silicon (M1/M2/M3)
#     ./build.sh intel        x86_64     — только Intel Mac
#     ./build.sh windows                 — не трогаем (см. AGENTS.md, §3.1)
# =============================================================================

# APP_NAME — имя для пользователя (как на сайте goblin.red), EXEC_NAME — внутреннее имя бинарника.
APP_NAME="GOBL(in) Drag"
EXEC_NAME="TwoFingerDrag"
BUNDLE_ID="com.local.twofingerdrag"
VERSION="1.0"
MIN_MACOS="13.0"

cd "$(dirname "$0")"


# --- Разбор режима сборки ----------------------------------------------------

MODE="${1:-universal}"

case "${MODE}" in
    arm|arm64|apple|silicon)
        MODE="arm"
        TARGETS=("arm64-apple-macosx${MIN_MACOS}")
        MODE_TITLE="Apple Silicon (arm64)"
        ;;
    intel|x86|x86_64)
        MODE="intel"
        TARGETS=("x86_64-apple-macosx${MIN_MACOS}")
        MODE_TITLE="Intel (x86_64)"
        ;;
    universal|fat|both)
        MODE="universal"
        TARGETS=("arm64-apple-macosx${MIN_MACOS}" "x86_64-apple-macosx${MIN_MACOS}")
        MODE_TITLE="Universal (arm64 + x86_64)"
        ;;
    windows|win)
        echo "==> Windows-сборку сейчас НЕ трогаем."
        echo "    Прототип для Windows — отдельный проект, в этом репозитории его нет."
        exit 0
        ;;
    -h|--help|help)
        echo "Использование: ./build.sh [arm|intel|universal|windows]"
        echo "  universal  — оба среза в одном бинарнике (по умолчанию)"
        echo "  arm        — только Apple Silicon, arm64"
        echo "  intel      — только Intel Mac, x86_64"
        echo "  windows    — не трогаем, только по отдельному запросу"
        exit 0
        ;;
    *)
        echo "Неизвестный режим сборки: ${MODE}" >&2
        echo "Доступно: universal (дефолт), arm, intel, windows" >&2
        exit 1
        ;;
esac

echo "==> Режим сборки: ${MODE_TITLE}"


# --- Подготовка бандла -------------------------------------------------------

SDK="$(xcrun --show-sdk-path)"
APP_DIR="${APP_NAME}.app"
BIN_PATH="${APP_DIR}/Contents/MacOS/${EXEC_NAME}"

echo "==> Подготовка бандла ${APP_DIR} ..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Логотип Goblin для меню и иконка приложения.
cp logo.svg AppIcon.icns "${APP_DIR}/Contents/Resources/"


# --- Генерация BuildInfo.swift ----------------------------------------------

echo "==> Генерация BuildInfo.swift ..."
BUILD_DATE="$(date '+%Y-%m-%d %H:%M:%S %Z')"
cat > Sources/TwoFingerDrag/BuildInfo.swift <<SWIFT
// Генерируется build.sh — не редактировать вручную.
enum BuildInfo {
    static let date = "${BUILD_DATE}"
    static let arch = "${MODE}"
}
SWIFT


# --- Список исходников -------------------------------------------------------

# SwiftPM под Command Line Tools недоступен (нет PlatformPath), компилируем напрямую swiftc.
SWIFT_FILES=()
while IFS= read -r file; do
    SWIFT_FILES+=("${file}")
done < <(find Sources/TwoFingerDrag -name '*.swift' -print | sort)


# --- Компиляция --------------------------------------------------------------

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

SLICES=()
for target in "${TARGETS[@]}"; do
    slice_name="${target%%-*}"          # arm64 / x86_64
    slice_path="${TMP_DIR}/${EXEC_NAME}-${slice_name}"

    echo "==> Компиляция среза ${slice_name} (swiftc, ${target}) ..."
    swiftc -O \
        -sdk "${SDK}" \
        -target "${target}" \
        "${SWIFT_FILES[@]}" \
        -o "${slice_path}"

    SLICES+=("${slice_path}")
done

if [ "${#SLICES[@]}" -gt 1 ]; then
    echo "==> Склейка срезов через lipo ..."
    lipo -create "${SLICES[@]}" -output "${BIN_PATH}"
else
    cp "${SLICES[0]}" "${BIN_PATH}"
fi


# --- Info.plist --------------------------------------------------------------

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>${EXEC_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Проверяем корректность plist.
plutil -lint "${APP_DIR}/Contents/Info.plist" >/dev/null


# --- Подпись -----------------------------------------------------------------

SIGN_ID="TwoFingerDrag Codesign"
if security find-identity -p codesigning 2>/dev/null | grep -q "${SIGN_ID}"; then
    echo "==> Подпись сертификатом ${SIGN_ID} (стабильная идентичность) ..."
    codesign --force --deep --sign "${SIGN_ID}" "${APP_DIR}"
else
    echo "==> Ad-hoc подпись (запусти ./create-cert.sh, чтобы разрешение не слетало) ..."
    codesign --force --deep --sign - "${APP_DIR}"
fi


# --- Итог --------------------------------------------------------------------

echo ""
echo "Готово: $(pwd)/${APP_DIR}"
echo "Архитектуры бинарника: $(lipo -archs "${BIN_PATH}")"
echo "Запуск:  open \"${APP_DIR}\""
