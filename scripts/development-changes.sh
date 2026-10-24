#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -ne 1 ]]; then
    echo "Usage: scripts/development-changes.sh <before-sha>" >&2
    exit 2
fi

# Compare with the download, not just the previous push: GitHub may replace a
# pending code run with a later docs run in the same concurrency group.
if git rev-parse --verify 'refs/tags/development^{commit}' >/dev/null 2>&1; then
    base="$(git rev-parse 'refs/tags/development^{commit}')"
    if git merge-base --is-ancestor "$base" HEAD; then
        :
    else
        result=$?
        if [[ $result -ne 1 ]]; then exit "$result"; fi
        printf 'true\n'
        exit 0
    fi
elif [[ "$1" =~ ^[0-9a-f]{40}$ && "$1" != 0000000000000000000000000000000000000000 ]] \
    && git cat-file -e "$1^{commit}" 2>/dev/null; then
    base="$1"
else
    # A first push or unavailable base must not silently skip a new app build.
    printf 'true\n'
    exit 0
fi

changed_paths="$(mktemp)"
trap 'rm -f "$changed_paths"' EXIT
# Renames must include the old path: moving code into docs also removes code.
git diff --no-renames --name-only -z "$base" HEAD -- > "$changed_paths"
while IFS= read -r -d '' path; do
    case "$path" in
        Sources/*|Tests/*|Tools/*|Packaging/*|scripts/*|Package.swift|Package.resolved|LICENSE|.github/workflows/*.yml|.github/workflows/*.yaml)
            printf 'true\n'
            exit 0
            ;;
    esac
done < "$changed_paths"
printf 'false\n'
