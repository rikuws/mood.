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

workdir="$(mktemp -d "${TMPDIR:-/tmp}/mood-distill-XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

empty_home="$workdir/empty-home"
mkdir -p "$empty_home"

fake_agent="$workdir/mood-agent"
printf '#!/bin/sh\necho ok\n' >"$fake_agent"
chmod +x "$fake_agent"

resolved="$(env HOME="$empty_home" PATH="/usr/bin:/bin" MOOD_AGENT="$fake_agent" "$script")"
assert_eq "$resolved" "$(resolved_path "$fake_agent")" \
    "MOOD_AGENT points at an executable helper"

legacy_agent="$workdir/pinax-agent"
printf '#!/bin/sh\necho ok\n' >"$legacy_agent"
chmod +x "$legacy_agent"
resolved="$(env -u MOOD_AGENT HOME="$empty_home" PATH="/usr/bin:/bin" PINAX_AGENT="$legacy_agent" "$script")"
assert_eq "$resolved" "$(resolved_path "$legacy_agent")" \
    "PINAX_AGENT still finds a legacy helper override"

bindir="$workdir/bin"
mkdir -p "$bindir"
cp "$fake_agent" "$bindir/mood-agent"
resolved="$(env -u MOOD_AGENT -u PINAX_AGENT HOME="$empty_home" PATH="$bindir:/usr/bin:/bin" "$script")"
assert_eq "$resolved" "$(resolved_path "$bindir/mood-agent")" \
    "PATH lookup finds mood-agent"

legacy_bindir="$workdir/legacy-bin"
mkdir -p "$legacy_bindir"
cp "$legacy_agent" "$legacy_bindir/pinax-agent"
resolved="$(env -u MOOD_AGENT -u PINAX_AGENT HOME="$empty_home" PATH="$legacy_bindir:/usr/bin:/bin" "$script")"
assert_eq "$resolved" "$(resolved_path "$legacy_bindir/pinax-agent")" \
    "PATH lookup still finds a legacy pinax-agent"

if env -u MOOD_AGENT -u PINAX_AGENT HOME="$empty_home" PATH="/usr/bin:/bin" \
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
