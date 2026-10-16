#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    printf 'Usage: %s <derived-data-dir> <destination-specifier>\n' "$0" >&2
    exit 2
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
derived_data=$(mkdir -p "$1" && CDPATH= cd -- "$1" && pwd -P)
destination=$2
developer_dir=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
xcodebuild="$developer_dir/usr/bin/xcodebuild"
products_dir="$derived_data/Build/Products/Debug-iphonesimulator"

test -x "$xcodebuild" || {
    printf 'xcodebuild is unavailable: %s\n' "$xcodebuild" >&2
    exit 1
}

# Derive TEST_HOST from the built host plist and inspect the actual product,
# host, runner, test-bundle plists, and .xctestrun before handing control to Xcode.
host_executable=MovUITestHost
if [ -f "$products_dir/MovUITestHost.app/Info.plist" ]; then
    host_executable=$(/usr/bin/plutil -extract CFBundleExecutable raw -o - \
        "$products_dir/MovUITestHost.app/Info.plist")
fi
test_host="$products_dir/MovUITestHost.app/$host_executable"

BUILT_PRODUCTS_DIR="$products_dir" \
TEST_HOST="$test_host" \
PRODUCT_BUNDLE_IDENTIFIER='local.mov.prototype.MovTests' \
    "$repo_root/scripts/verify-ui-test-isolation.sh"

products_root=$(dirname "$products_dir")
set -- "$products_root"/Mov_*.xctestrun
test -f "$1" && test "$#" -eq 1 || {
    printf 'Expected one build-for-testing .xctestrun beside %s.\n' "$products_dir" >&2
    exit 1
}
xctestrun=$1

# Run only the focused UI cases. This wrapper is the only supported entry point
# for test-without-building; it rechecks the real product/host/test artifacts on
# every invocation, directly before executing the tests.
"$xcodebuild" test-without-building -xctestrun "$xctestrun" \
    -destination "$destination" -parallel-testing-enabled NO \
    -only-testing:MovUITests/LaunchTests/testProfilePhotoUploadCanBeCancelledWithoutApplyingLateResult \
    -only-testing:MovUITests/LaunchTests/testProfilePhotoFailureIsVisibleAndLeavesEditorAvailable \
    -only-testing:MovUITests/LaunchTests/testShareOutputPNGCanBeAttachedToCommunityDraft \
    -only-testing:MovUITests/LaunchTests/testCommunityPublishBusyPreventsReturningToEditableComposer \
    -only-testing:MovUITests/LaunchTests/testCommunityAmbiguousCreateRemainsBlockedInPreview
