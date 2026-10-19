#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    printf 'Usage: %s <built-products-dir>\n' "$0" >&2
    exit 2
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
products_dir=$(CDPATH= cd -- "$1" 2>/dev/null && pwd -P) || {
    printf 'Built-products directory is missing: %s\n' "$1" >&2
    exit 1
}
project="$repo_root/Mov.xcodeproj"
configuration=${CONFIGURATION:-Debug}
sdk=${SDK_NAME:-iphonesimulator}
override='local.mov.prototype.command-line-override'
developer_dir=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
xcodebuild="$developer_dir/usr/bin/xcodebuild"
test_host="$products_dir/MovUITestHost.app/MovUITestHost"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/mov-ui-test-override.XXXXXX")
settings="$tmp_dir/build-settings.txt"
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

# Missing build artifacts must fail closed instead of falling back to project
# strings or a presumed simulator bundle ID.
if BUILT_PRODUCTS_DIR="$tmp_dir/missing-products" \
    TEST_HOST="$tmp_dir/missing-products/MovUITestHost.app/MovUITestHost" \
    PRODUCT_BUNDLE_IDENTIFIER='local.mov.prototype.MovTests' \
    "$repo_root/scripts/verify-ui-test-isolation.sh"; then
    printf 'Isolation gate accepted a missing build-products directory.\n' >&2
    exit 1
fi

# First require a clean baseline. This prevents missing or malformed artifacts
# from making the command-line override check pass for the wrong reason.
BUILT_PRODUCTS_DIR="$products_dir" \
TEST_HOST="$test_host" \
PRODUCT_BUNDLE_IDENTIFIER='local.mov.prototype.MovTests' \
    "$repo_root/scripts/verify-ui-test-isolation.sh"

"$xcodebuild" -project "$project" -target MovUITestHost -configuration "$configuration" -sdk "$sdk" \
    -showBuildSettings "PRODUCT_BUNDLE_IDENTIFIER=$override" > "$settings" 2>/dev/null
resolved_override=$(awk -F ' = ' '$1 ~ /^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER$/ { value=$2 } END { print value }' "$settings")
test "$resolved_override" = "$override" || {
    printf 'xcodebuild did not resolve the requested command-line bundle-ID override (got %s)\n' "$resolved_override" >&2
    exit 1
}

products_root=$(dirname "$products_dir")
products_dir_name=$(basename "$products_dir")
tmp_products_root="$tmp_dir/Products"
tmp_products_dir="$tmp_products_root/$products_dir_name"
mkdir -p "$tmp_products_dir"
cp -R "$products_dir/MovUITestHost.app" "$tmp_products_dir/MovUITestHost.app"
ln -s "$products_dir/MovUITests-Runner.app" "$tmp_products_dir/MovUITests-Runner.app"
set -- "$products_root"/MovUITestHost_*.xctestrun
test -f "$1" || {
    printf 'MovUITestHost build-for-testing configuration is missing: %s\n' "$products_root" >&2
    exit 1
}
test "$#" -eq 1 || {
    printf 'expected one MovUITestHost .xctestrun configuration, found %s\n' "$#" >&2
    exit 1
}
cp "$1" "$tmp_products_root/$(basename "$1")"
/usr/bin/plutil -replace CFBundleIdentifier -string "$resolved_override" \
    "$tmp_products_dir/MovUITestHost.app/Info.plist"

if BUILT_PRODUCTS_DIR="$tmp_products_dir" \
    TEST_HOST="$tmp_products_dir/MovUITestHost.app/MovUITestHost" \
    PRODUCT_BUNDLE_IDENTIFIER='local.mov.prototype.MovTests' \
    "$repo_root/scripts/verify-ui-test-isolation.sh" >"$tmp_dir/isolation-output.txt" 2>&1; then
    cat "$tmp_dir/isolation-output.txt" >&2
    printf 'Isolation gate accepted a command-line PRODUCT_BUNDLE_IDENTIFIER override.\n' >&2
    exit 1
fi

if ! /usr/bin/grep -Fq "test host built CFBundleIdentifier is '$resolved_override'" "$tmp_dir/isolation-output.txt"; then
    cat "$tmp_dir/isolation-output.txt" >&2
    printf 'Isolation gate rejected the command-line override for an unexpected reason.\n' >&2
    exit 1
fi

printf 'Negative check passed: host-only artifacts reject an xcodebuild PRODUCT_BUNDLE_IDENTIFIER override without a Mov.app product.\n'
