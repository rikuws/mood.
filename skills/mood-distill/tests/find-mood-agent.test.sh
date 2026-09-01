#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
script="$root/scripts/find-mood-agent.sh"
failures=0

assert_eq() {
    local actual="$1" expected="$2" message="$3"
    if [[ "$actual" != "$expected" ]]; then
        printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$message" "$expected" "$actual" >&2
        failures=$((failures + 1))
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" message="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'FAIL %s\n  missing: %s\n  in: %s\n' "$message" "$needle" "$haystack" >&2
        failures=$((failures + 1))
    fi
}

resolved_path() {
    local path="$1"
    if command -v realpath >/dev/null 2>&1; then
        realpath "$path"
    else
        printf '%s/%s\n' "$(cd "$(dirname "$path")" && pwd)" "$(basename "$path")"
    fi
}

write_compatible_agent() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    printf '%s\n' \
        '#!/bin/sh' \
        'if [ "${1:-}" = "--help" ]; then' \
        '  echo "Usage: mood-agent projects [--pretty] | mood-agent inspiration --id <uuid> [--pretty] | mood-agent validate-essence --file <path> [--pretty]"' \
        '  exit 0' \
        'fi' \
        'echo ok' >"$path"
    chmod +x "$path"
}

write_incompatible_agent() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    printf '%s\n' \
        '#!/bin/sh' \
        'if [ "${1:-}" = "--help" ]; then' \
        '  echo "Usage: pinax-agent projects [--pretty] | pinax-agent inspirations --project <name-or-uuid> [--pretty]"' \
        '  exit 0' \
        'fi' \
        'echo ok' >"$path"
    chmod +x "$path"
}

workdir="$(mktemp -d "${TMPDIR:-/tmp}/mood-distill-XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

empty_home="$workdir/empty-home"
mkdir -p "$empty_home"

fake_agent="$workdir/mood-agent"
write_compatible_agent "$fake_agent"

resolved="$(env HOME="$empty_home" PATH="/usr/bin:/bin" MOOD_AGENT="$fake_agent" "$script")"
assert_eq "$resolved" "$(resolved_path "$fake_agent")" \
    "MOOD_AGENT points at an executable helper"

legacy_agent="$workdir/pinax-agent"
write_compatible_agent "$legacy_agent"
resolved="$(env -u MOOD_AGENT HOME="$empty_home" PATH="/usr/bin:/bin" PINAX_AGENT="$legacy_agent" "$script")"
assert_eq "$resolved" "$(resolved_path "$legacy_agent")" \
    "PINAX_AGENT still finds a legacy helper override"

bindir="$workdir/bin"
mkdir -p "$bindir"
cp "$fake_agent" "$bindir/mood-agent"
resolved="$(env -u MOOD_AGENT -u PINAX_AGENT MOOD_AGENT_SKIP_APP_SEARCH=1 HOME="$empty_home" PATH="$bindir:/usr/bin:/bin" "$script")"
assert_eq "$resolved" "$(resolved_path "$bindir/mood-agent")" \
    "PATH lookup finds mood-agent"

legacy_bindir="$workdir/legacy-bin"
mkdir -p "$legacy_bindir"
cp "$legacy_agent" "$legacy_bindir/pinax-agent"
resolved="$(env -u MOOD_AGENT -u PINAX_AGENT MOOD_AGENT_SKIP_APP_SEARCH=1 HOME="$empty_home" PATH="$legacy_bindir:/usr/bin:/bin" "$script")"
assert_eq "$resolved" "$(resolved_path "$legacy_bindir/pinax-agent")" \
    "PATH lookup still finds a legacy pinax-agent"

legacy_applications="$workdir/system-applications"
legacy_app_agent="$legacy_applications/Pinax.app/Contents/Helpers/pinax-agent"
write_compatible_agent "$legacy_app_agent"
resolved="$(env -u MOOD_AGENT -u PINAX_AGENT \
    MOOD_AGENT_SYSTEM_APPLICATIONS_DIR="$legacy_applications" \
    MOOD_AGENT_USER_APPLICATIONS_DIR="$workdir/user-applications" \
    MOOD_AGENT_SKIP_MDFIND=1 \
    HOME="$empty_home" PATH="/usr/bin:/bin" "$script")"
assert_eq "$resolved" "$(resolved_path "$legacy_app_agent")" \
    "explicit legacy Pinax.app helper path remains supported"

old_agent="$workdir/old-install/mood-agent"
write_incompatible_agent "$old_agent"
if env HOME="$empty_home" PATH="/usr/bin:/bin" MOOD_AGENT="$old_agent" \
    "$script" >"$workdir/old-stdout" 2>"$workdir/old-stderr"; then
    printf 'FAIL incompatible helper should exit nonzero\n' >&2
    failures=$((failures + 1))
else
    assert_eq "$(cat "$workdir/old-stdout")" "" \
        "incompatible helper prints nothing on stdout"
    old_error="$(cat "$workdir/old-stderr")"
    assert_contains "$old_error" "too old for mood-distill 2.0" \
        "incompatible helper explains the upgrade requirement"
    assert_contains "$old_error" "inspiration --id" \
        "incompatible helper names the saved-item capability"
    assert_contains "$old_error" "validate-essence --file" \
        "incompatible helper names the validation capability"
fi

old_applications="$workdir/old-system-applications"
old_app_agent="$old_applications/mood.app/Contents/Helpers/pinax-agent"
write_incompatible_agent "$old_app_agent"
if env -u MOOD_AGENT -u PINAX_AGENT \
    MOOD_AGENT_SYSTEM_APPLICATIONS_DIR="$old_applications" \
    MOOD_AGENT_USER_APPLICATIONS_DIR="$workdir/old-user-applications" \
    MOOD_AGENT_SKIP_MDFIND=1 HOME="$empty_home" PATH="/usr/bin:/bin" \
    "$script" >"$workdir/old-app-stdout" 2>"$workdir/old-app-stderr"; then
    printf 'FAIL discovered incompatible app helper should exit nonzero\n' >&2
    failures=$((failures + 1))
else
    assert_eq "$(cat "$workdir/old-app-stdout")" "" \
        "discovered incompatible app helper prints nothing on stdout"
    old_app_error="$(cat "$workdir/old-app-stderr")"
    assert_contains "$old_app_error" "$(resolved_path "$old_app_agent")" \
        "upgrade error identifies the discovered incompatible helper"
    assert_contains "$old_app_error" "too old for mood-distill 2.0" \
        "discovered incompatible app helper requests an upgrade"
fi

if env -u MOOD_AGENT -u PINAX_AGENT MOOD_AGENT_SKIP_APP_SEARCH=1 HOME="$empty_home" PATH="/usr/bin:/bin" \
    "$script" >"$workdir/stdout" 2>"$workdir/stderr"; then
    printf 'FAIL missing helper should exit nonzero\n' >&2
    failures=$((failures + 1))
else
    assert_eq "$(cat "$workdir/stdout")" "" "missing helper prints nothing on stdout"
    assert_contains "$(cat "$workdir/stderr")" "Could not find mood.'s mood-agent helper" \
        "missing helper explains how to recover"
fi

if [[ "$failures" -ne 0 ]]; then
    printf '%s test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'ok\n'
