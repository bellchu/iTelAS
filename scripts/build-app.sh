#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
SCRATCH_DIR="${TMPDIR:-/tmp}/itelas-release-build"
OUTPUT_DIR="$PROJECT_DIR/dist"
APP_DIR="$OUTPUT_DIR/iTelAS.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
SOURCE_ICNS="$PROJECT_DIR/Resources/iTelAS.icns"
SOURCE_ICON_PNG="$PROJECT_DIR/Resources/iTelASIcon.png"
ASSET_CATALOG="$PROJECT_DIR/Resources/Assets.xcassets"
ASSET_OUTPUT_DIR="$SCRATCH_DIR/icon-assets"
ASSET_INFO_PLIST="$SCRATCH_DIR/icon-assets.plist"
ASSET_MANIFEST="$SCRATCH_DIR/icon-assets.json"

[[ -s "$SOURCE_ICNS" ]] || { print -u2 "Missing nonempty app icon: $SOURCE_ICNS"; exit 1; }
[[ -s "$SOURCE_ICON_PNG" ]] || { print -u2 "Missing nonempty app icon fallback: $SOURCE_ICON_PNG"; exit 1; }
[[ -s "$ASSET_CATALOG/AppIcon.appiconset/Contents.json" ]] \
    || { print -u2 "Missing AppIcon asset catalog metadata."; exit 1; }
[[ "$(dd if="$SOURCE_ICNS" bs=1 skip=8 count=4 2>/dev/null)" == "ic12" ]] \
    || { print -u2 "The app icon is not the canonical iconutil-generated ICNS container."; exit 1; }
[[ "$(sips -g pixelWidth "$SOURCE_ICON_PNG" 2>/dev/null | awk '/pixelWidth/ { print $2 }')" == "1024" ]] \
    || { print -u2 "The master app icon must be a 1024-pixel PNG."; exit 1; }

CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/itelas-clang-cache" \
SWIFT_MODULECACHE_PATH="${TMPDIR:-/tmp}/itelas-swift-cache" \
swift build \
    --package-path "$PROJECT_DIR" \
    --configuration release \
    --arch arm64 \
    --disable-sandbox \
    --scratch-path "$SCRATCH_DIR"

mkdir -p "$ASSET_OUTPUT_DIR"
xcrun actool "$ASSET_CATALOG" \
    --compile "$ASSET_OUTPUT_DIR" \
    --platform macosx \
    --minimum-deployment-target 15.0 \
    --app-icon AppIcon \
    --development-region en \
    --output-partial-info-plist "$ASSET_INFO_PLIST" \
    >/dev/null
[[ -s "$ASSET_OUTPUT_DIR/Assets.car" ]] \
    || { print -u2 "Asset catalog compiler did not produce Assets.car."; exit 1; }
xcrun assetutil --info "$ASSET_OUTPUT_DIR/Assets.car" > "$ASSET_MANIFEST"
[[ "$(rg -c '\"RenditionName\" : \"icon_' "$ASSET_MANIFEST")" == "10" ]] \
    || { print -u2 "Compiled AppIcon does not contain all ten macOS renditions."; exit 1; }

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp -f "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp -f "$SOURCE_ICNS" "$RESOURCES_DIR/iTelAS.icns"
cp -f "$SOURCE_ICON_PNG" "$RESOURCES_DIR/iTelASIcon.png"
cp -f "$ASSET_OUTPUT_DIR/Assets.car" "$RESOURCES_DIR/Assets.car"
cp -f "$SCRATCH_DIR/arm64-apple-macosx/release/iTelAS" "$MACOS_DIR/iTelAS"
chmod 755 "$MACOS_DIR/iTelAS"
touch "$APP_DIR"

plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP_DIR/Contents/Info.plist")" == "iTelAS.icns" ]] \
    || { print -u2 "Info.plist does not declare the packaged iTelAS icon."; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$APP_DIR/Contents/Info.plist")" == "AppIcon" ]] \
    || { print -u2 "Info.plist does not declare the compiled AppIcon asset."; exit 1; }
cmp -s "$SOURCE_ICNS" "$RESOURCES_DIR/iTelAS.icns" \
    || { print -u2 "Packaged ICNS differs from the source icon."; exit 1; }
cmp -s "$SOURCE_ICON_PNG" "$RESOURCES_DIR/iTelASIcon.png" \
    || { print -u2 "Packaged PNG differs from the source icon fallback."; exit 1; }
[[ -s "$RESOURCES_DIR/Assets.car" ]] \
    || { print -u2 "Packaged asset catalog is missing."; exit 1; }

CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/itelas-icon-verify-clang-cache" \
SWIFT_MODULECACHE_PATH="${TMPDIR:-/tmp}/itelas-icon-verify-swift-cache" \
swift "$PROJECT_DIR/scripts/verify-app-icon.swift" \
    "$RESOURCES_DIR/iTelASIcon.png" \
    "$RESOURCES_DIR/iTelAS.icns"

codesign --force --sign - "$APP_DIR"
file "$MACOS_DIR/iTelAS"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

print "Built $APP_DIR"
