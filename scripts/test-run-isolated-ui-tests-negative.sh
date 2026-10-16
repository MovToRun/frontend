#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/mov-isolated-ui-negative.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

if DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer} \
    "$repo_root/scripts/run-isolated-ui-tests.sh" "$tmp_dir/empty-derived-data" \
    'platform=iOS Simulator,name=iPhone 17' >"$tmp_dir/output.txt" 2>&1; then
    cat "$tmp_dir/output.txt" >&2
    printf 'UI-test wrapper accepted missing build-for-testing artifacts.\n' >&2
    exit 1
fi

if ! /usr/bin/grep -q 'built-products directory is missing\|build-for-testing configuration is missing\|Expected one build-for-testing' "$tmp_dir/output.txt"; then
    cat "$tmp_dir/output.txt" >&2
    printf 'UI-test wrapper failed before reaching the built-artifact isolation gate.\n' >&2
    exit 1
fi

if /usr/bin/grep -q 'Test Suite\|Testing started\|test-without-building' "$tmp_dir/output.txt"; then
    cat "$tmp_dir/output.txt" >&2
    printf 'UI-test wrapper reached test execution before the isolation gate passed.\n' >&2
    exit 1
fi

printf 'Negative check passed: wrapper rejects missing built artifacts before test execution.\n'
