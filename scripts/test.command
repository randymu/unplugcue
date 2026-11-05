#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
XCODE_ROOT="${XCODE_ROOT:-/Applications/Xcode.app/Contents/Developer}"
FRAMEWORKS="${XCODE_ROOT}/Platforms/MacOSX.platform/Developer/Library/Frameworks"
LIBRARIES="${XCODE_ROOT}/Platforms/MacOSX.platform/Developer/usr/lib"
cd "${ROOT_DIR}"
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
export CLANG_MODULE_CACHE_PATH="${ROOT_DIR}/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="${ROOT_DIR}/.build/ModuleCache"

# Command Line Tools build the app; Xcode supplies XCTest without changing the system developer selection.
swift build --disable-sandbox --build-tests \
  -Xswiftc -F -Xswiftc "${FRAMEWORKS}" -Xswiftc -I -Xswiftc "${LIBRARIES}" \
  -Xlinker -rpath -Xlinker "${FRAMEWORKS}" \
  -Xlinker -L -Xlinker "${LIBRARIES}" -Xlinker -rpath -Xlinker "${LIBRARIES}"
BIN_DIR="$(swift build --show-bin-path)"
"${XCODE_ROOT}/usr/bin/xctest" "${BIN_DIR}/LaCieSafeOffPackageTests.xctest"
