#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
script="$root/scripts/find-pinax-agent.sh"
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

workdir="$(mktemp -d "${TMPDIR:-/tmp}/mood-distill-XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

fake_agent="$workdir/pinax-agent"
printf '#!/bin/sh\necho ok\n' >"$fake_agent"
chmod +x "$fake_agent"

resolved="$(PINAX_AGENT="$fake_agent" "$script")"
if command -v realpath >/dev/null 2>&1; then
    expected="$(realpath "$fake_agent")"
else
    expected="$(cd "$(dirname "$fake_agent")" && pwd)/$(basename "$fake_agent")"
fi
assert_eq "$resolved" "$expected" "PINAX_AGENT points at an executable helper"

empty_home="$workdir/empty-home"
mkdir -p "$empty_home"
if HOME="$empty_home" PATH="/usr/bin:/bin" PINAX_AGENT="$workdir/missing" \
    "$script" >"$workdir/stdout" 2>"$workdir/stderr"; then
    printf 'FAIL missing helper should exit nonzero\n' >&2
    failures=$((failures + 1))
else
    assert_eq "$(cat "$workdir/stdout")" "" "missing helper prints nothing on stdout"
    assert_contains "$(cat "$workdir/stderr")" "Could not find mood.'s pinax-agent helper" \
        "missing helper explains how to recover"
fi

if [[ "$failures" -ne 0 ]]; then
    printf '%s test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'ok\n'
