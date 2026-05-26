#!/bin/bash
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DEST="/Applications/yubi-pass.app"
BUNDLE_ID="marromlam.yubi-pass"
DERIVED_DATA=~/Library/Developer/Xcode/DerivedData

echo "==> Stopping yubi-pass and Safari..."
pkill -x "yubi-pass" 2>/dev/null || true
pkill -x "Safari" 2>/dev/null || true
sleep 1

echo "==> Wiping DerivedData for yubi-pass..."
rm -rf "$DERIVED_DATA"/yubi-pass-*/ 2>/dev/null || true

echo "==> Cleaning and building..."
cd "$REPO_DIR/safari/yubi-pass"
xcodebuild -project yubi-pass.xcodeproj \
  -scheme "yubi-pass (macOS)" \
  -configuration Release \
  -allowProvisioningUpdates \
  clean build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"

APP_SRC=$(find "$DERIVED_DATA" -name "yubi-pass.app" -path "*/Build/Products/Release/yubi-pass.app" 2>/dev/null | head -1)

if [ -z "$APP_SRC" ]; then
  echo "ERROR: Could not find built app in DerivedData"
  exit 1
fi

echo "==> Installing from: $APP_SRC"
rm -rf "$APP_DEST"
mv "$APP_SRC" "$APP_DEST"

echo "==> Clearing quarantine..."
xattr -rd com.apple.quarantine "$APP_DEST" 2>/dev/null || true

echo "==> Removing all stale Safari extension instances..."
WEBEXT_DIR=~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebExtensions
find "$WEBEXT_DIR" -mindepth 2 -maxdepth 2 -name "*yubi-pass*" -type d 2>/dev/null | while read d; do
    echo "    Removing: $d"
    rm -rf "$d"
done
rm -rf ~/Library/Containers/marromlam.yubi-pass.Extension 2>/dev/null || true
rm -rf ~/Library/Caches/marromlam.yubi-pass 2>/dev/null || true
rm -rf ~/Library/Caches/marromlam.yubi-pass.Extension 2>/dev/null || true
pluginkit -e use -i "$BUNDLE_ID.Extension" 2>/dev/null || true

echo "==> Launching app..."
open "$APP_DEST"
sleep 2

echo "==> Relaunching Safari..."
open -a Safari

echo ""
echo "Done. In Safari → Settings → Extensions:"
echo "  - Toggle yubi-pass OFF then ON to reload the extension"
