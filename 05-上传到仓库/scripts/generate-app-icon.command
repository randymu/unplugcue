#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SOURCE="${ROOT_DIR}/scripts/generate-app-icon.swift"
RESOURCES="${ROOT_DIR}/Resources"
MASTER="${RESOURCES}/AppIcon-1024.png"
ICONSET="${RESOURCES}/AppIcon.iconset"
COMPILER="${ROOT_DIR}/.build/icon-generator"

mkdir -p "${RESOURCES}" "${ROOT_DIR}/.build"
export CLANG_MODULE_CACHE_PATH="${ROOT_DIR}/.build/IconModuleCache"
xcrun swiftc "${SOURCE}" -o "${COMPILER}"
"${COMPILER}" "${MASTER}"

rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"

for spec in \
  "16 icon_16x16.png" \
  "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" \
  "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" \
  "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" \
  "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" \
  "1024 icon_512x512@2x.png"
do
  pixels="${spec%% *}"
  filename="${spec#* }"
  sips -z "${pixels}" "${pixels}" "${MASTER}" --out "${ICONSET}/${filename}" >/dev/null
done

if ! iconutil -c icns "${ICONSET}" -o "${RESOURCES}/AppIcon.icns" 2>/dev/null; then
  /usr/bin/python3 "${ROOT_DIR}/scripts/make-icns.py" \
    "${ICONSET}" "${RESOURCES}/AppIcon.icns"
fi
rm -rf "${ICONSET}"

echo "Generated: ${RESOURCES}/AppIcon.icns"
