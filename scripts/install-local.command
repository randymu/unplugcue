#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_NAME="UnplugCue.app"
BUILD_DIR="${ROOT_DIR}/.build/release"
APP_DIR="${HOME}/Applications/${APP_NAME}"

cd "${ROOT_DIR}"
if [[ -d /Library/Developer/CommandLineTools ]]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
export CLANG_MODULE_CACHE_PATH="${ROOT_DIR}/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="${ROOT_DIR}/.build/ModuleCache"
swift build --disable-sandbox -c release

STAGED_APP="${ROOT_DIR}/.build/staged/${APP_NAME}"
rm -rf "${STAGED_APP}"
mkdir -p "${STAGED_APP}/Contents/MacOS" "${STAGED_APP}/Contents/Resources"
ditto "${BUILD_DIR}/LaCieSafeOff" "${STAGED_APP}/Contents/MacOS/LaCieSafeOff"
ditto "${ROOT_DIR}/Resources/Info.plist" "${STAGED_APP}/Contents/Info.plist"
ditto "${ROOT_DIR}/Resources/AppIcon.icns" "${STAGED_APP}/Contents/Resources/AppIcon.icns"
ditto "${ROOT_DIR}/LICENSE" "${STAGED_APP}/Contents/Resources/LICENSE.txt"
codesign --force --deep --sign - "${STAGED_APP}"
codesign --verify --deep --strict "${STAGED_APP}"

if [[ -f "${APP_DIR}/Contents/Info.plist" && -x "${APP_DIR}/Contents/MacOS/LaCieSafeOff" ]]; then
  BACKUP="${ROOT_DIR}/.build/app-backups/$(date +%Y%m%d-%H%M%S)/${APP_NAME}"
  ditto "${APP_DIR}" "${BACKUP}"
  echo "Previous app backed up: ${BACKUP}"
fi
pkill -x LaCieSafeOff 2>/dev/null || true
if pgrep -x LaCieSafeOff >/dev/null; then
  echo "Please quit UnplugCue before installing. No app files were replaced."
  exit 1
fi
rm -rf "${APP_DIR}/Contents"
mkdir -p "${APP_DIR}"
if ! ditto "${STAGED_APP}" "${APP_DIR}"; then
  if [[ -n "${BACKUP:-}" ]]; then ditto "${BACKUP}" "${APP_DIR}"; fi
  echo "Installation failed; previous app restored when available."
  exit 1
fi

codesign --verify --deep --strict "${APP_DIR}"
touch "${APP_DIR}"
"/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" \
  -f "${APP_DIR}" >/dev/null 2>&1 || true
if [[ "${SAFE_OFF_NO_OPEN:-0}" != "1" ]]; then open "${APP_DIR}"; fi

echo "Installed: ${APP_DIR}"
