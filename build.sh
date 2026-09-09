#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/clang-cache"
swift build -c release --product LingDesktop --disable-sandbox --scratch-path .build --cache-path .build/cache --config-path .build/config --security-path .build/security
APP_PATH="$PROJECT_DIR/dist/LingDesktop.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp .build/release/LingDesktop "$APP_PATH/Contents/MacOS/LingDesktop"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
codesign --force --sign - "$APP_PATH"
printf '已构建：%s\n运行：open "%s"\n' "$APP_PATH" "$APP_PATH"
