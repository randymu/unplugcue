#!/bin/zsh
set -euo pipefail

pkill -x LaCieSafeOff 2>/dev/null || true
rm -rf "${HOME}/Applications/UnplugCue.app"
rm -rf "${HOME}/Library/Application Support/LaCieSafeOff"
defaults delete com.randymu.LaCieSafeOff 2>/dev/null || true

echo "UnplugCue has been completely removed."
