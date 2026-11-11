#!/bin/zsh
set -eu
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"

SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version)
MIN_MACOS=13.0

swift build -c release --disable-sandbox -debug-info-format none "$@"

BIN_DIR=$(swift build -c release "$@" --show-bin-path)
APP="$PWD/dist/InputRedirection.app"
mkdir -p "$PWD/dist"
STAGING_DIR=$(mktemp -d "$PWD/dist/.inputredirection-build.XXXXXX")
cleanup() {
    # Restore the previous build if installing the new bundle fails.
    if [[ -d "$STAGING_DIR/previous.app" && ! -e "$APP" ]]; then
        mv "$STAGING_DIR/previous.app" "$APP" || return
    fi
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT
STAGED_APP="$STAGING_DIR/InputRedirection.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
swift scripts/render-icon.swift Resources/Icons/AppIcon.svg "$STAGING_DIR/AppIcon.iconset"
iconutil --convert icns "$STAGING_DIR/AppIcon.iconset" \
    --output "$STAGED_APP/Contents/Resources/AppIcon.icns"
# Never overwrite signed code in place: use a fresh inode and sign the complete
# staged bundle before replacing the previous build (Apple: Updating Mac Software).
VTOOL_ARCHS=()
for arch in $(lipo -archs "$BIN_DIR/InputRedirection"); do
    VTOOL_ARCHS+=(-arch "$arch")
done
xcrun vtool "${VTOOL_ARCHS[@]}" -set-build-version macos "$MIN_MACOS" "$SDK_VERSION" -replace \
    -output "$STAGED_APP/Contents/MacOS/InputRedirection" "$BIN_DIR/InputRedirection"
chmod +x "$STAGED_APP/Contents/MacOS/InputRedirection"
cp -R "$BIN_DIR/InputRedirection_InputRedirection.bundle" "$STAGED_APP/Contents/Resources/"
cp Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
codesign --force --sign - "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
if [[ -e "$APP" ]]; then
    mv "$APP" "$STAGING_DIR/previous.app"
fi
mv "$STAGED_APP" "$APP"
echo "Built $APP"
