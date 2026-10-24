#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
configuration="${1:-release}"
if [[ "$configuration" != "release" && "$configuration" != "debug" ]]; then
    echo "Usage: scripts/build.sh [release|debug]" >&2
    exit 2
fi
if [[ -n "${BLINK_BUNDLE_VERSION:-}" && ! "$BLINK_BUNDLE_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] \
    || [[ -n "${BLINK_CHANNEL:-}" && "$BLINK_CHANNEL" != "release" && "$BLINK_CHANNEL" != "development" ]] \
    || [[ -n "${BLINK_SOURCE_REVISION:-}" && ! "$BLINK_SOURCE_REVISION" =~ ^[0-9a-f]{40}$ ]]; then
    echo "build: BLINK_BUNDLE_VERSION must be one to three dot-separated integers, BLINK_CHANNEL release or development, and BLINK_SOURCE_REVISION a full lowercase commit SHA." >&2
    exit 2
fi
swift build -c "$configuration" --arch arm64
binary_path="$(swift build -c "$configuration" --arch arm64 --show-bin-path)"
build_dir="${BLINK_BUILD_DIR:-$PWD/build}"
mkdir -p "$build_dir"
build_dir="$(cd "$build_dir" && pwd)"
bundle_path="$build_dir/Blink.app"
mkdir -p "$bundle_path/Contents/MacOS" "$bundle_path/Contents/Resources"
cp "$binary_path/Blink" "$bundle_path/Contents/MacOS/Blink"
cp Packaging/Info.plist "$bundle_path/Contents/Info.plist"
# Optional identity for packaged downloads, applied to this bundle copy before
# signing. The tracked Info.plist is never modified.
plist="$bundle_path/Contents/Info.plist"
[[ -z "${BLINK_BUNDLE_VERSION:-}" ]] || /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BLINK_BUNDLE_VERSION" "$plist"
[[ -z "${BLINK_CHANNEL:-}" ]] || /usr/libexec/PlistBuddy -c "Add :BlinkChannel string $BLINK_CHANNEL" "$plist"
[[ -z "${BLINK_SOURCE_REVISION:-}" ]] || /usr/libexec/PlistBuddy -c "Add :BlinkSourceRevision string $BLINK_SOURCE_REVISION" "$plist"
cp LICENSE "$bundle_path/Contents/Resources/LICENSE"
swift Tools/make-icon.swift "$build_dir/AppIcon.iconset"
iconutil -c icns "$build_dir/AppIcon.iconset" -o "$bundle_path/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$bundle_path"
codesign --verify --strict "$bundle_path"
echo "Built $bundle_path"
