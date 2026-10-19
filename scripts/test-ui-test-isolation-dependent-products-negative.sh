#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/mov-dependent-products-negative.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
products_dir="$tmp_dir/Build/Products/Debug-iphonesimulator"
mkdir -p "$products_dir/MovUITestHost.app/PlugIns/MovTests.xctest" \
    "$products_dir/MovUITests-Runner.app/PlugIns/MovUITests.xctest"

make_bundle() {
    bundle=$1
    bundle_id=$2
    executable=$3
    mkdir -p "$bundle"
    /usr/bin/plutil -create xml1 "$bundle/Info.plist"
    /usr/bin/plutil -insert CFBundleIdentifier -string "$bundle_id" "$bundle/Info.plist"
    /usr/bin/plutil -insert CFBundleExecutable -string "$executable" "$bundle/Info.plist"
    : >"$bundle/$executable"
    chmod +x "$bundle/$executable"
}

make_bundle "$products_dir/MovUITestHost.app" local.mov.prototype.MovUITestHost MovUITestHost
make_bundle "$products_dir/MovUITestHost.app/PlugIns/MovTests.xctest" local.mov.prototype.MovTests MovTests
make_bundle "$products_dir/MovUITests-Runner.app" local.mov.prototype.MovUITests-Runner MovUITests-Runner
make_bundle "$products_dir/MovUITests-Runner.app/PlugIns/MovUITests.xctest" local.mov.prototype.MovUITests MovUITests

write_xctestrun() {
    bad_target=$1
    python3 - "$tmp_dir/Build/Products/MovUITestHost_isolation_negative.xctestrun" "$bad_target" <<'PY'
import plistlib
import sys

output_path, bad_target = sys.argv[1:]
products = "__TESTROOT__/Debug-iphonesimulator"
product_app = f"{products}/Mov.app"
host_app = f"{products}/MovUITestHost.app"
ui_runner = f"{products}/MovUITests-Runner.app"
unit_bundle = "__TESTHOST__/PlugIns/MovTests.xctest"
ui_bundle = "__TESTHOST__/PlugIns/MovUITests.xctest"

def dependent_paths(target):
    paths = [
        f"{products}/MovUITestHost.app",
        f"{products}/MovUITestHost.app/PlugIns/MovTests.xctest",
        f"{products}/MovUITests-Runner.app",
        f"{products}/MovUITests-Runner.app/PlugIns/MovUITests.xctest",
    ]
    if target == bad_target:
        paths.insert(0, product_app)
    return paths

configuration = {
    "MovTests": {
        "TestHostPath": host_app,
        "TestHostBundleIdentifier": "local.mov.prototype.MovUITestHost",
        "TestBundlePath": unit_bundle,
        "DependentProductPaths": dependent_paths("MovTests"),
    },
    "MovUITests": {
        "TestHostPath": ui_runner,
        "TestHostBundleIdentifier": "local.mov.prototype.MovUITests-Runner",
        "UITargetAppPath": host_app,
        "TestBundlePath": ui_bundle,
        "DependentProductPaths": dependent_paths("MovUITests"),
    },
}
with open(output_path, "wb") as output_file:
    plistlib.dump(configuration, output_file, fmt=plistlib.FMT_XML)
PY
}

for target in MovTests MovUITests; do
    write_xctestrun "$target"
    if BUILT_PRODUCTS_DIR="$products_dir" \
        TEST_HOST="$products_dir/MovUITestHost.app/MovUITestHost" \
        PRODUCT_BUNDLE_IDENTIFIER=local.mov.prototype.MovTests \
        "$repo_root/scripts/verify-ui-test-isolation.sh" >"$tmp_dir/output.txt" 2>&1; then
        cat "$tmp_dir/output.txt" >&2
        printf 'Isolation gate accepted Mov.app in %s.DependentProductPaths.\n' "$target" >&2
        exit 1
    fi

    if ! /usr/bin/grep -Fq "$target DependentProductPaths references the production Mov.app" "$tmp_dir/output.txt"; then
        cat "$tmp_dir/output.txt" >&2
        printf 'Isolation gate failed for an unexpected reason while checking %s.\n' "$target" >&2
        exit 1
    fi
done

printf 'Negative checks passed: gate rejects Mov.app references in both unit and UI DependentProductPaths before test execution.\n'
