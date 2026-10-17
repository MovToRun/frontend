#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ui_tests="$repo_root/MovUITests/LaunchTests.swift"
scheme="$repo_root/Mov.xcodeproj/xcshareddata/xcschemes/Mov.xcscheme"
project="$repo_root/Mov.xcodeproj/project.pbxproj"

fail() {
    printf 'UI-test isolation check failed: %s\n' "$1" >&2
    exit 1
}

require_env() {
    eval 'value=${'"$1"'-}'
    test -n "$value" || fail "Xcode did not supply required resolved setting $1"
}

require_env BUILT_PRODUCTS_DIR
require_env TEST_HOST
require_env PRODUCT_BUNDLE_IDENTIFIER

products_dir=$(CDPATH= cd -- "$BUILT_PRODUCTS_DIR" 2>/dev/null && pwd -P) \
    || fail "built-products directory is missing: $BUILT_PRODUCTS_DIR"
case "$TEST_HOST" in
    /*) ;;
    *) fail "resolved TEST_HOST is not an absolute path: $TEST_HOST" ;;
esac
case "$TEST_HOST" in
    *'$('*|*'${'*) fail "resolved TEST_HOST contains an unexpanded build variable: $TEST_HOST" ;;
esac

expected_product_id='com.movtorun.mov'
expected_host_id='local.mov.prototype.MovUITestHost'
expected_unit_test_id='local.mov.prototype.MovTests'
expected_ui_test_id='local.mov.prototype.MovUITests'

test "$PRODUCT_BUNDLE_IDENTIFIER" = "$expected_unit_test_id" \
    || fail "resolved test-action bundle ID is '$PRODUCT_BUNDLE_IDENTIFIER', expected $expected_unit_test_id (a command-line build-setting override may be active)"

# The production app stays a normal Run/Archive target, but it must not be in
# the build-for-testing product graph. Its identity is checked from project
# settings; the test build must not materialize Mov.app at all.
product_id_occurrences=$(/usr/bin/grep -F -c "PRODUCT_BUNDLE_IDENTIFIER = $expected_product_id;" "$project" || true)
test "$product_id_occurrences" -eq 2 \
    || fail "project no longer declares the production bundle ID $expected_product_id in both app configurations"

plist_value() {
    /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null \
        || fail "missing or unreadable $2 in built plist: $1"
}

source_product_id=$(plist_value "$repo_root/Mov/Info.plist" CFBundleIdentifier)
test "$source_product_id" = '$(PRODUCT_BUNDLE_IDENTIFIER)' \
    || fail "source product Info.plist uses unexpected CFBundleIdentifier '$source_product_id'"

verify_app() {
    bundle=$1
    expected_id=$2
    expected_name=$3
    label=$4
    plist="$bundle/Info.plist"
    test -d "$bundle" || fail "$label artifact is missing: $bundle"
    test -f "$plist" || fail "$label Info.plist is missing: $plist"
    bundle_id=$(plist_value "$plist" CFBundleIdentifier)
    executable=$(plist_value "$plist" CFBundleExecutable)
    if [ "$expected_id" != '-' ]; then
        test "$bundle_id" = "$expected_id" \
            || fail "$label built CFBundleIdentifier is '$bundle_id', expected $expected_id"
    fi
    if [ "$expected_name" != '-' ]; then
        test "$executable" = "$expected_name" \
            || fail "$label built CFBundleExecutable is '$executable', expected $expected_name"
    fi
    test -x "$bundle/$executable" \
        || fail "$label executable is missing or not executable: $bundle/$executable"
}

verify_test_bundle() {
    bundle=$1
    expected_id=$2
    label=$3
    test -d "$bundle" || fail "$label test bundle is missing: $bundle"
    plist="$bundle/Info.plist"
    if [ ! -f "$plist" ] && [ -f "$bundle/Contents/Info.plist" ]; then
        plist="$bundle/Contents/Info.plist"
    fi
    test -f "$plist" || fail "$label test-bundle Info.plist is missing: $bundle"
    bundle_id=$(plist_value "$plist" CFBundleIdentifier)
    executable=$(plist_value "$plist" CFBundleExecutable)
    test "$bundle_id" = "$expected_id" \
        || fail "$label test-bundle CFBundleIdentifier is '$bundle_id', expected $expected_id"
    test -x "$bundle/$executable" || test -x "$bundle/Contents/MacOS/$executable" \
        || fail "$label test-bundle executable is missing: $executable"
}

host_app="$products_dir/MovUITestHost.app"
ui_runner="$products_dir/MovUITests-Runner.app"
unit_bundle="$host_app/PlugIns/MovTests.xctest"
ui_bundle="$ui_runner/PlugIns/MovUITests.xctest"
products_root=$(dirname "$products_dir")
set -- "$products_root"/Mov_*.xctestrun
test -f "$1" || fail "build-for-testing configuration is missing beside built products: $products_root"
test "$#" -eq 1 || fail "expected one Mov .xctestrun configuration, found $#"
xctestrun=$1

if [ -e "$products_dir/Mov.app" ] || [ -L "$products_dir/Mov.app" ]; then
    fail "production app artifact must be excluded from build-for-testing products: $products_dir/Mov.app"
fi
verify_app "$host_app" "$expected_host_id" MovUITestHost 'test host'
verify_app "$ui_runner" - - 'UI test runner'
verify_test_bundle "$unit_bundle" "$expected_unit_test_id" 'unit test'
verify_test_bundle "$ui_bundle" "$expected_ui_test_id" 'UI test'

host_executable=$(plist_value "$host_app/Info.plist" CFBundleExecutable)
expected_test_host="$host_app/$host_executable"
test -x "$TEST_HOST" || fail "resolved TEST_HOST executable is missing or not executable: $TEST_HOST"
test_host_parent=$(CDPATH= cd -- "$(dirname -- "$TEST_HOST")" 2>/dev/null && pwd -P) \
    || fail "resolved TEST_HOST parent directory is missing: $TEST_HOST"
normalized_test_host="$test_host_parent/$(basename -- "$TEST_HOST")"
test "$normalized_test_host" = "$expected_test_host" \
    || fail "resolved TEST_HOST '$TEST_HOST' does not equal the built host executable '$expected_test_host'"
host_app_executable=$(basename "$normalized_test_host")
test "$host_app_executable" = "$host_executable" \
    || fail "resolved TEST_HOST executable '$host_app_executable' differs from host plist executable '$host_executable'"

runner_id=$(plist_value "$ui_runner/Info.plist" CFBundleIdentifier)
runner_executable=$(plist_value "$ui_runner/Info.plist" CFBundleExecutable)
test "$runner_id" != "$expected_product_id" || fail 'UI runner bundle ID collides with product app'
test "$runner_id" != "$expected_host_id" || fail 'UI runner bundle ID collides with test host'
test "$runner_id" != "$expected_unit_test_id" || fail 'UI runner bundle ID collides with unit-test bundle'
test "$runner_id" != "$expected_ui_test_id" || fail 'UI runner bundle ID collides with UI-test bundle'
test "$runner_executable" = "$(basename "$ui_runner/$runner_executable")" \
    || fail 'UI runner executable name is not a simple bundle executable'

xctestrun_value() {
    /usr/bin/plutil -extract "$1" raw -o - "$xctestrun" 2>/dev/null \
        || fail "missing $1 in build-for-testing configuration: $xctestrun"
}

xctestrun_array_json() {
    /usr/bin/plutil -extract "$1" json -o - "$xctestrun" 2>/dev/null \
        || fail "missing $1 in build-for-testing configuration: $xctestrun"
}

verify_no_product_app_dependencies() {
    target=$1
    dependencies=$(xctestrun_array_json "$target.DependentProductPaths")
    if printf '%s\n' "$dependencies" | /usr/bin/grep -Eiq '(^|[/"])Mov[.]app([/"]|$)'; then
        fail "$target DependentProductPaths references the production Mov.app: $dependencies"
    fi
}

verify_no_product_app_dependencies MovTests
verify_no_product_app_dependencies MovUITests

resolve_testroot_path() {
    case "$1" in
        __TESTROOT__/*) printf '%s/%s\n' "$products_root" "${1#__TESTROOT__/}" ;;
        /*) printf '%s\n' "$1" ;;
        *) fail "test-run configuration contains an unresolved/nonabsolute product path: $1" ;;
    esac
}

unit_test_host=$(resolve_testroot_path "$(xctestrun_value MovTests.TestHostPath)")
unit_test_host_id=$(xctestrun_value MovTests.TestHostBundleIdentifier)
unit_test_bundle_path=$(xctestrun_value MovTests.TestBundlePath)
test "$unit_test_host" = "$host_app" \
    || fail "built unit-test runner targets '$unit_test_host', expected $host_app"
test "$unit_test_host_id" = "$expected_host_id" \
    || fail "unit-test runner host bundle ID is '$unit_test_host_id', expected $expected_host_id"
test "$unit_test_bundle_path" = '__TESTHOST__/PlugIns/MovTests.xctest' \
    || fail "unit-test bundle path is not inside the isolated host: $unit_test_bundle_path"

ui_test_runner_path=$(resolve_testroot_path "$(xctestrun_value MovUITests.TestHostPath)")
ui_test_runner_id=$(xctestrun_value MovUITests.TestHostBundleIdentifier)
ui_target_app=$(resolve_testroot_path "$(xctestrun_value MovUITests.UITargetAppPath)")
ui_test_bundle_path=$(xctestrun_value MovUITests.TestBundlePath)
test "$ui_test_runner_path" = "$ui_runner" \
    || fail "built UI-test runner targets '$ui_test_runner_path', expected $ui_runner"
test "$ui_test_runner_id" = "$runner_id" \
    || fail "UI-test runner config ID is '$ui_test_runner_id', built runner ID is '$runner_id'"
test "$ui_target_app" = "$host_app" \
    || fail "UI-test target app is '$ui_target_app', expected isolated host $host_app"
test "$ui_test_bundle_path" = '__TESTHOST__/PlugIns/MovUITests.xctest' \
    || fail "UI-test bundle path is not inside the isolated runner: $ui_test_bundle_path"

if ! /usr/bin/perl -0e '
    use strict;
    my ($source_path, $scheme_path) = @ARGV;
    local $/;
    open my $source_file, "<", $source_path or die "Cannot read $source_path: $!\n";
    my $source = <$source_file>;
    open my $scheme_file, "<", $scheme_path or die "Cannot read $scheme_path: $!\n";
    my $scheme = <$scheme_file>;

    my @suite_literals = $source =~ /"-wire-test-store-suite"\s*,\s*"([^\"]+)"/g;
    for my $suite (@suite_literals) {
        die "Static UserDefaults suite must include a per-run UUID: $suite\n"
            unless $suite =~ /UUID\(\)\.uuidString/;
    }
    while ($source =~ /\b(?:let|var)\s+([A-Za-z_]\w*[Ss]uite)\s*=\s*"([^\"]+)"/g) {
        my ($name, $suite) = ($1, $2);
        die "Suite variable $name must include a per-run UUID: $suite\n"
            unless $suite =~ /UUID\(\)\.uuidString/;
    }
    while ($source =~ /\b(?:let|var)\s+service\s*=\s*"([^\"]+)"/g) {
        die "Fixture Keychain service must include a per-run UUID: $1\n"
            unless $1 =~ /UUID\(\)\.uuidString/;
    }
    die "Fixture suite helper must append a UUID\n"
        unless $source =~ /func\s+makeFixtureStoreSuite[\s\S]{0,160}UUID\(\)\.uuidString/;
    die "Publish-busy fixture suite must end in a standalone UUID component\n"
        unless index($source, q{let suite="mov.wireframe.test.publish-busy.\(UUID().uuidString)"}) >= 0;
    die "Ambiguous-create fixture suite must end in a standalone UUID component\n"
        unless index($source, q{let suite="mov.wireframe.test.create-unknown.\(UUID().uuidString)"}) >= 0;
    die "Profile-cancel fixture suite must end in a standalone UUID component\n"
        unless index($source, q{let suite="mov.wireframe.test.profile-photo-cancel.\(UUID().uuidString)"}) >= 0;
    die "Profile-failure fixture suite must end in a standalone UUID component\n"
        unless index($source, q{let suite="mov.wireframe.test.profile-photo-failure.\(UUID().uuidString)"}) >= 0;
    die "Auth fixture Keychain service helper must append a UUID\n"
        unless $source =~ /let\s+service\s*=\s*"com\.movtorun\.ui-fixture\.auth-session\.[^\"]*UUID\(\)\.uuidString[^\"]*"/;
    die "Auth fixture launch must pass its UUID suite and Keychain service\n"
        unless $source =~ /func\s+authSessionFixtureArguments[\s\S]{0,400}-wire-auth-session-fixture-service[\s\S]{0,160}service[\s\S]{0,160}-wire-test-store-suite[\s\S]{0,80}suite/;
    die "TestAction must invoke this preflight and build its environment from MovTests\n"
        unless $scheme =~ /<EnvironmentBuildable>[\s\S]*?BlueprintName = "MovTests"[\s\S]*?<\/EnvironmentBuildable>/
            && $scheme =~ /verify-ui-test-isolation\.sh/;
    die "TestAction must include both unit and UI test targets\n"
        unless $scheme =~ /BlueprintName = "MovTests"/ && $scheme =~ /BlueprintName = "MovUITests"/;
    die "The product app must be excluded from build-for-testing while the isolated host remains included\n"
        unless $scheme =~ /<BuildActionEntry\s+buildForTesting = "NO"[\s\S]*?BlueprintName = "Mov"\s*\n/
            && $scheme =~ /<BuildActionEntry\s+buildForTesting = "YES"[\s\S]*?BlueprintName = "MovUITestHost"/;
' "$ui_tests" "$scheme"; then
    fail 'test artifacts exist, but UUID-scoped UserDefaults/Keychain launch configuration or TestAction wiring is invalid'
fi

printf 'Verified no Mov.app test artifact or DependentProductPaths reference, test host/runner/bundle plists, resolved TEST_HOST executable, build-for-testing host paths, and UUID-scoped fixtures.\n'
