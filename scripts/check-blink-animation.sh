#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
# Run after swift build/test has built BlinkCore. Compile the actual presentation
# sources into a native AppKit probe, without relaunching the user's Blink app.
# Do not call swift build here: when this script runs inside `swift test`, the
# outer SwiftPM process holds the .build lock and the nested call deadlocks.
# The .build/debug link exists under both build engines.
bin_path=".build/debug"
if [[ -d "$bin_path/Modules" ]]; then
    # Legacy native build system: modules under Modules/, objects per target.
    module_dir="$bin_path/Modules"
    objects=("$bin_path"/BlinkCore.build/*.o)
else
    # Swift Build engine (default since Swift 6.4): module and object at the top level.
    module_dir="$bin_path"
    objects=("$bin_path/BlinkCore.o")
fi
if [[ ! -d "$module_dir/BlinkCore.swiftmodule" || ! -f "${objects[0]}" ]]; then
    echo "check-blink-animation: BlinkCore debug artifacts not found under $bin_path; run 'swift build' first (a debug build)." >&2
    exit 3
fi
probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/blink-animation-check.XXXXXX")"
trap 'rm -rf "$probe_dir"' EXIT
swiftc -swift-version 6 -parse-as-library -D BLINK_ANIMATION_PROBE -I "$module_dir" \
    Sources/Blink/UI/Design.swift Sources/Blink/UI/BreakPresentation.swift Sources/Blink/UI/BlinkCueView.swift \
    Sources/Blink/UI/OverlayController.swift Tools/BlinkAnimationCheck.swift \
    "${objects[@]}" -o "$probe_dir/check"
"$probe_dir/check"
