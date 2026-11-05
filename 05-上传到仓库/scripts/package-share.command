#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
export CLANG_MODULE_CACHE_PATH="${ROOT_DIR}/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="${ROOT_DIR}/.build/ModuleCache"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ROOT_DIR}/Resources/Info.plist")"
NAME="UnplugCue-${VERSION}-macOS-universal"
DEST="${ROOT_DIR}/Distribution/${NAME}"
APP="${DEST}/UnplugCue.app"
[[ ! -e "${DEST}" && ! -e "${DEST}.zip" ]] || { print "Package already exists: ${DEST}"; exit 1; }

cd "${ROOT_DIR}"
for ARCH in arm64 x86_64; do
  swift build --disable-sandbox -c release --triple "${ARCH}-apple-macosx14.0" \
    --scratch-path ".build/share-${ARCH}"
done

mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
lipo -create \
  .build/share-arm64/arm64-apple-macosx/release/LaCieSafeOff \
  .build/share-x86_64/x86_64-apple-macosx/release/LaCieSafeOff \
  -output "${APP}/Contents/MacOS/LaCieSafeOff"
strip -S "${APP}/Contents/MacOS/LaCieSafeOff"
ditto Resources/Info.plist "${APP}/Contents/Info.plist"
ditto Resources/AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"
ditto LICENSE "${APP}/Contents/Resources/LICENSE.txt"
ditto LICENSE "${DEST}/LICENSE.txt"
ditto docs/Friend-Readme.txt "${DEST}/Read-Me.txt"
ditto docs/Friend-Readme.en.txt "${DEST}/Read-Me-English.txt"
codesign --force --sign - "${APP}"
codesign --verify --deep --strict "${APP}"
lipo -info "${APP}/Contents/MacOS/LaCieSafeOff"
ditto -c -k --norsrc --keepParent "${DEST}" "${DEST}.zip"
shasum -a 256 "${DEST}.zip"
print "Created: ${DEST}.zip"
