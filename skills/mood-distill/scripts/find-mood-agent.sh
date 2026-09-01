#!/usr/bin/env bash
# Locate mood.'s bundled mood-agent helper and print its absolute path.
# Compatible with macOS system bash 3.2.
set -euo pipefail

is_agent() {
    local path="$1"
    [ -n "$path" ] && [ -f "$path" ] && [ -x "$path" ]
}

supports_required_commands() {
    local path="$1"
    local help_output
    if ! help_output="$("$path" --help 2>/dev/null)"; then
        return 1
    fi
    case "$help_output" in
        *"inspiration --id"*) ;;
        *) return 1 ;;
    esac
    case "$help_output" in
        *"validate-essence --file"*) ;;
        *) return 1 ;;
    esac
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

incompatible_agent=""

incompatible_error() {
    local path="$1"
    cat >&2 <<EOF
Found a mood. helper at:

  ${path}

but it is too old for mood-distill 2.0. A compatible helper must advertise:

  inspiration --id <uuid>
  validate-essence --file <path>

Upgrade mood. for Mac, then retry. The current helper was rejected and will not be used.
EOF
    exit 1
}

consider() {
    local candidate="$1"
    local required="${2:-0}"
    [ -n "$candidate" ] || return 0
    if is_agent "$candidate"; then
        if supports_required_commands "$candidate"; then
            resolve_path "$candidate"
            exit 0
        fi
        if [ -z "$incompatible_agent" ]; then
            incompatible_agent="$(resolve_path "$candidate")"
        fi
        if [ "$required" = "1" ]; then
            incompatible_error "$incompatible_agent"
        fi
    fi
}

consider_helpers() {
    local root="$1"
    [ -n "$root" ] || return 0
    consider "${root}/mood-agent"
    consider "${root}/pinax-agent"
}

if [ -n "${MOOD_AGENT:-}" ]; then
    consider "$MOOD_AGENT" 1
fi
if [ -n "${PINAX_AGENT:-}" ]; then
    consider "$PINAX_AGENT" 1
fi

if [ "${MOOD_AGENT_SKIP_APP_SEARCH:-0}" != "1" ]; then
    system_applications="${MOOD_AGENT_SYSTEM_APPLICATIONS_DIR:-/Applications}"
    user_applications="${MOOD_AGENT_USER_APPLICATIONS_DIR:-${HOME}/Applications}"

    consider_helpers "${system_applications}/mood.app/Contents/Helpers"
    consider_helpers "${user_applications}/mood.app/Contents/Helpers"
    consider_helpers "${system_applications}/Pinax.app/Contents/Helpers"
    consider_helpers "${user_applications}/Pinax.app/Contents/Helpers"

    if [ "${MOOD_AGENT_SKIP_MDFIND:-0}" != "1" ] \
        && command -v mdfind >/dev/null 2>&1; then
        while IFS= read -r app; do
            [ -n "$app" ] || continue
            consider_helpers "${app}/Contents/Helpers"
        done <<EOF
$(mdfind 'kMDItemCFBundleIdentifier == "com.rikuwikman.Pinax"' 2>/dev/null || true)
EOF
    fi
fi

if command -v mood-agent >/dev/null 2>&1; then
    consider "$(command -v mood-agent)"
fi
if command -v pinax-agent >/dev/null 2>&1; then
    consider "$(command -v pinax-agent)"
fi

if [ -n "$incompatible_agent" ]; then
    incompatible_error "$incompatible_agent"
fi

cat >&2 <<'EOF'
Could not find mood.'s mood-agent helper.

Install mood. for Mac, then retry. A signed app exposes:

  /Applications/mood.app/Contents/Helpers/mood-agent

Older compatible installs may live at:

  /Applications/Pinax.app/Contents/Helpers/mood-agent
  /Applications/Pinax.app/Contents/Helpers/pinax-agent

Override the path with MOOD_AGENT if the helper lives elsewhere. Unsigned
Debug helpers read ~/Library/Application Support/Pinax unless PINAX_STORAGE_DIRECTORY
is set; they cannot see the production App Group library.
EOF
exit 1
