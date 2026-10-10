#!/bin/sh
set -eu

plist_path=${1:?Usage: verify-app-plist.sh <Info.plist> <expected build version> <expected marketing version>}
expected_build=${2:?Usage: verify-app-plist.sh <Info.plist> <expected build version> <expected marketing version>}
expected_marketing=${3:?Usage: verify-app-plist.sh <Info.plist> <expected build version> <expected marketing version>}

if [ ! -f "$plist_path" ]; then
    printf 'Info.plist not found: %s\n' "$plist_path" >&2
    exit 1
fi

actual_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist_path")
actual_marketing=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist_path")

if [ "$actual_build" != "$expected_build" ]; then
    printf 'CFBundleVersion mismatch: expected %s, got %s\n' "$expected_build" "$actual_build" >&2
    exit 1
fi

if [ "$actual_marketing" != "$expected_marketing" ]; then
    printf 'CFBundleShortVersionString mismatch: expected %s, got %s\n' "$expected_marketing" "$actual_marketing" >&2
    exit 1
fi

printf 'Verified CFBundleVersion=%s and CFBundleShortVersionString=%s in %s\n' \
    "$actual_build" "$actual_marketing" "$plist_path"
