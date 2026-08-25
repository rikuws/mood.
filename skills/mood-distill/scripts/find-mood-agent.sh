#!/usr/bin/env bash
# Locate mood.'s bundled mood-agent helper and print its absolute path.
# Compatible with macOS system bash 3.2.
set -euo pipefail

is_agent() {
    local path="$1"
    [ -n "$path" ] && [ -f "$path" ] && [ -x "$path" ]
}

resolve_path() {
    local path="$1"
    if command -v realpath >/dev/null 2>&1; then
        realpath "$path"
        return
    fi
    local dir base
    dir="$(cd "$(dirname "$path")" && pwd)"
    base="$(basename "$path")"
    printf '%s/%s\n' "$dir" "$base"
}

consider() {
    local candidate="$1"
    [ -n "$candidate" ] || return 0
    if is_agent "$candidate"; then
        resolve_path "$candidate"
        exit 0
    fi
}

consider_helpers() {
    local root="$1"
    [ -n "$root" ] || return 0
    consider "${root}/mood-agent"
    consider "${root}/pinax-agent"
}

consider "${MOOD_AGENT:-}"
consider "${PINAX_AGENT:-}"
consider_helpers "/Applications/mood.app/Contents/Helpers"
consider_helpers "${HOME}/Applications/mood.app/Contents/Helpers"

if command -v mdfind >/dev/null 2>&1; then
    while IFS= read -r app; do
        [ -n "$app" ] || continue
        consider_helpers "${app}/Contents/Helpers"
    done <<EOF
$(mdfind 'kMDItemCFBundleIdentifier == "com.rikuwikman.Pinax"' 2>/dev/null || true)
EOF
fi

if command -v mood-agent >/dev/null 2>&1; then
    consider "$(command -v mood-agent)"
fi
if command -v pinax-agent >/dev/null 2>&1; then
    consider "$(command -v pinax-agent)"
fi

cat >&2 <<'EOF'
Could not find mood.'s mood-agent helper.

Install mood. for Mac, then retry. A signed app exposes:

  /Applications/mood.app/Contents/Helpers/mood-agent

Override the path with MOOD_AGENT if the helper lives elsewhere. Unsigned
Debug helpers read ~/Library/Application Support/Pinax unless PINAX_STORAGE_DIRECTORY
is set; they cannot see the production App Group library.
EOF
exit 1
