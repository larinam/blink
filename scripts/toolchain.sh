#!/bin/bash
# Sourced by the build scripts. Blink needs Xcode 27's toolchain: the SwiftUI
# macro plugins (@State and friends) ship only inside Xcode.app, so a
# Command Line Tools-only developer directory cannot compile the app.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    active_dir="$(xcode-select -p 2>/dev/null || true)"
    if [[ "$active_dir" != *"/Contents/Developer" ]]; then
        if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
            export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
            echo "toolchain: active developer directory is '$active_dir'; using $DEVELOPER_DIR" >&2
        else
            echo "toolchain: Xcode 27 is required. Install it and run: sudo xcode-select -s /Applications/Xcode.app" >&2
            exit 3
        fi
    fi
fi
xcode_version="$(xcodebuild -version 2>/dev/null | awk '/^Xcode/ {print $2}' || true)"
if [[ -z "$xcode_version" || "${xcode_version%%.*}" -lt 27 ]]; then
    echo "toolchain: Xcode 27 or newer is required (found '${xcode_version:-none}')." >&2
    exit 3
fi
