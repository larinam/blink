#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
    echo "Usage: scripts/package-release.sh [expected-version]" >&2
    echo "       scripts/package-release.sh --development <run>.<attempt> <full-source-sha>" >&2
    exit 2
}
channel=release
if [[ "${1:-}" == "--development" ]]; then
    [[ $# -eq 3 ]] || usage
    channel=development
    build_id="$2"
    revision="$3"
    if [[ ! "$build_id" =~ ^[0-9]+\.[0-9]+$ || ! "$revision" =~ ^[0-9a-f]{40}$ ]]; then
        echo "package-release: development mode needs <run>.<attempt> and a full lowercase commit SHA." >&2
        exit 2
    fi
else
    [[ $# -le 1 ]] || usage
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Packaging/Info.plist)"
minimum_macos="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Packaging/Info.plist)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$build_number" =~ ^[0-9]+$ \
    || ! "$minimum_macos" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "package-release: Info.plist must contain a numeric major.minor.patch version, build number, and minimum macOS version." >&2
    exit 2
fi
if [[ $channel == release && $# -eq 1 && "$1" != "$version" ]]; then
    echo "package-release: requested version '$1' does not match Info.plist version '$version'." >&2
    exit 2
fi

# The recorded source revision must describe exactly what is packaged: SwiftPM
# would also compile an untracked source file, so only ignored files may differ.
if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
    echo "package-release: commit or remove changed and untracked files before packaging." >&2
    exit 2
fi
head="$(git rev-parse HEAD)"
if [[ $channel == development ]]; then
    if [[ "$revision" != "$head" ]]; then
        echo "package-release: requested revision $revision is not the checked-out commit $head." >&2
        exit 2
    fi
    bundle_version="$build_number.$build_id"
    short="${revision:0:12}"
    archive="Blink-${version}-development.${bundle_version}-${short}-macos-arm64.zip"
    checksum="SHA256SUMS-development.${bundle_version}-${short}.txt"
    output_dir="$PWD/build/releases/development"
    title="Blink $version development build $bundle_version ($short)"
    note="This Development build was produced automatically from the \`main\` branch after its default tests passed. The next Development build replaces it, and it can be less stable than a numbered release."
    build_id_json="\"$build_id\""
else
    revision="$head"
    bundle_version="$build_number"
    archive="Blink-${version}-build.${build_number}-macos-arm64.zip"
    checksum="SHA256SUMS.txt"
    output_dir="$PWD/build/releases/v$version"
    title="Blink $version (build $build_number)"
    note="This numbered release is fixed: its download is never replaced."
    build_id_json=null
fi
if [[ -e "$output_dir" ]]; then
    echo "package-release: $output_dir already exists; move it aside before packaging again." >&2
    exit 3
fi

mkdir -p "$PWD/build/releases"
staging_root="$(mktemp -d "$PWD/build/.blink-release.XXXXXX")"
trap 'rm -rf "$staging_root"' EXIT
mkdir -p "$staging_root/package" "$staging_root/output" "$staging_root/verify"

# Assemble into a fresh directory so an existing local app or old bundle resource
# cannot enter the release. The normal build/Blink.app is left untouched.
BLINK_BUILD_DIR="$staging_root/products" BLINK_BUNDLE_VERSION="$bundle_version" BLINK_CHANNEL="$channel" \
    BLINK_SOURCE_REVISION="$revision" scripts/build.sh release
bundle="$staging_root/products/Blink.app"
if [[ "$(lipo -archs "$bundle/Contents/MacOS/Blink")" != "arm64" ]]; then
    echo "package-release: expected an arm64-only executable." >&2
    exit 3
fi
signature="$(codesign -dvv "$bundle" 2>&1)"
if [[ "$signature" != *"Signature=adhoc"* ]]; then
    echo "package-release: expected the ad-hoc signature described in the installation notes." >&2
    exit 3
fi

ditto "$bundle" "$staging_root/package/Blink.app"
cp LICENSE "$staging_root/package/LICENSE"
escape() { printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'; }
sed -e "s|@RELEASE_TITLE@|$(escape "$title")|g" \
    -e "s|@CHANNEL_NOTE@|$(escape "$note")|g" \
    -e "s|@MINIMUM_MACOS@|$minimum_macos|g" \
    -e "s|@ARCHIVE@|$archive|g" \
    -e "s|@CHECKSUM@|$checksum|g" \
    -e "s|@SOURCE_REF@|$revision|g" \
    Packaging/INSTALL.md > "$staging_root/package/INSTALL.md"
if grep -q '@[A-Z_]*@' "$staging_root/package/INSTALL.md"; then
    echo "package-release: INSTALL.md has an unrendered placeholder." >&2
    exit 3
fi
cp "$staging_root/package/INSTALL.md" "$staging_root/output/release-notes.md"

ditto -c -k --sequesterRsrc "$staging_root/package" "$staging_root/output/$archive"

# Verify the app after the same ZIP round trip a recipient performs. Do not
# launch it here: that could affect the developer's windows and saved state.
ditto -x -k "$staging_root/output/$archive" "$staging_root/verify"
extracted="$staging_root/verify/Blink.app"
codesign --verify --strict "$extracted"
test -x "$extracted/Contents/MacOS/Blink"
cmp "$bundle/Contents/MacOS/Blink" "$extracted/Contents/MacOS/Blink"
cmp LICENSE "$extracted/Contents/Resources/LICENSE"
cmp LICENSE "$staging_root/verify/LICENSE"
cmp "$staging_root/package/INSTALL.md" "$staging_root/verify/INSTALL.md"
info="$extracted/Contents/Info.plist"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")" != "$bundle_version" \
    || "$(/usr/libexec/PlistBuddy -c 'Print :BlinkChannel' "$info")" != "$channel" \
    || "$(/usr/libexec/PlistBuddy -c 'Print :BlinkSourceRevision' "$info")" != "$revision" ]]; then
    echo "package-release: the packaged bundle does not carry the expected build identity." >&2
    exit 3
fi
(
    cd "$staging_root/output"
    shasum -a 256 "$archive" > "$checksum"
    shasum -a 256 -c "$checksum"
)
cat > "$staging_root/output/build-info.json" <<JSON
{
  "channel": "$channel",
  "version": "$version",
  "bundle_version": "$bundle_version",
  "build_id": $build_id_json,
  "source_revision": "$revision",
  "archive": "$archive",
  "checksum": "$checksum",
  "minimum_macos": "$minimum_macos"
}
JSON

# Publish the complete local artifact set only after all packaging checks pass.
mv "$staging_root/output" "$output_dir"
echo "Packaged $output_dir/$archive"
echo "Checksum: $output_dir/$checksum"
echo "Release notes: $output_dir/release-notes.md"
echo "Build info: $output_dir/build-info.json"
