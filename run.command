#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -x "$PROJECT_DIR/dist/LingDesktop.app/Contents/MacOS/LingDesktop" ]; then
    bash "$PROJECT_DIR/build.sh"
fi
open "$PROJECT_DIR/dist/LingDesktop.app"
