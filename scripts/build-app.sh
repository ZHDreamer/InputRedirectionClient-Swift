#!/bin/zsh
set -eu
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build -c release --disable-sandbox -debug-info-format none
BIN_DIR=$(swift build -c release --show-bin-path)
APP="$PWD/dist/InputRedirection.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/InputRedirection" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
