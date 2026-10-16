#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
project="$repo_root/Mov.xcodeproj/project.pbxproj"
plist="$repo_root/Mov/Info.plist"
ui_tests="$repo_root/MovUITests/LaunchTests.swift"
scheme="$repo_root/Mov.xcodeproj/xcshareddata/xcschemes/Mov.xcscheme"

fail() {
    printf 'UI-test isolation check failed: %s\n' "$1" >&2
    exit 1
}

contains() {
    grep -Fq -- "$1" "$2"
}

count_occurrences() {
    grep -Fc -- "$1" "$2" || true
}

contains 'PRODUCT_BUNDLE_IDENTIFIER = com.movtorun.mov;' "$project" || fail 'product app bundle ID changed'
contains '<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>' "$plist" || fail 'app Info.plist no longer resolves its bundle ID from the build setting'
contains 'PRODUCT_BUNDLE_IDENTIFIER = local.mov.prototype.MovUITestHost;' "$project" || fail 'isolated test host bundle ID is missing'
test "$(count_occurrences 'PRODUCT_BUNDLE_IDENTIFIER = com.movtorun.mov;' "$project")" -eq 2 || fail 'both product configurations must retain com.movtorun.mov'
test "$(count_occurrences 'PRODUCT_BUNDLE_IDENTIFIER = local.mov.prototype.MovUITestHost;' "$project")" -eq 2 || fail 'both isolated test-host configurations must use the separate ID'
test "$(count_occurrences 'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/MovUITestHost.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/MovUITestHost";' "$project")" -eq 2 || fail 'unit test Debug and Release must host inside MovUITestHost'
test "$(count_occurrences 'TEST_TARGET_NAME = MovUITestHost;' "$project")" -eq 2 || fail 'UI test Debug and Release must target MovUITestHost'
if grep -Fq 'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Mov.app/' "$project"; then
    fail 'a host test target still uses Mov.app'
fi
contains 'verify-ui-test-isolation.sh' "$scheme" || fail 'the Xcode TestAction must run this check before tests'

for runner_id in local.mov.prototype.MovTests local.mov.prototype.MovUITests; do
    test "$(count_occurrences "PRODUCT_BUNDLE_IDENTIFIER = $runner_id;" "$project")" -eq 2 || fail "both test runner configurations must use $runner_id"
    if [ "$runner_id" = 'com.movtorun.mov' ] || [ "$runner_id" = 'local.mov.prototype.MovUITestHost' ]; then
        fail "test runner ID overlaps a product or host ID: $runner_id"
    fi
done

if ! /usr/bin/perl -0e '
    use strict;
    my $path = shift;
    local $/;
    open my $fh, "<", $path or die "Cannot read $path: $!\n";
    my $source = <$fh>;
    my @suite_literals = $source =~ /"-wire-test-store-suite"\s*,\s*"([^"]+)"/g;
    for my $suite (@suite_literals) {
        die "Static UserDefaults suite must include a per-run UUID: $suite\n"
            unless $suite =~ /UUID\(\)\.uuidString/;
    }
    while ($source =~ /\b(?:let|var)\s+([A-Za-z_]\w*[Ss]uite)\s*=\s*"([^"]+)"/g) {
        my ($name, $suite) = ($1, $2);
        die "Suite variable $name must include a per-run UUID: $suite\n"
            unless $suite =~ /UUID\(\)\.uuidString/;
    }
    while ($source =~ /\b(?:let|var)\s+service\s*=\s*"([^"]+)"/g) {
        die "Fixture Keychain service must include a per-run UUID: $1\n"
            unless $1 =~ /UUID\(\)\.uuidString/;
    }
    die "Fixture suite helper must append a UUID\n"
        unless $source =~ /func\s+makeFixtureStoreSuite[\s\S]{0,160}UUID\(\)\.uuidString/;
    die "Auth fixture Keychain service helper must append a UUID\n"
        unless $source =~ /let\s+service\s*=\s*"com\.movtorun\.ui-fixture\.auth-session\.[^"]*UUID\(\)\.uuidString[^"]*"/;
' "$ui_tests"; then
    fail 'UserDefaults suites or fixture Keychain services are not UUID-isolated'
fi

printf 'Verified isolated UI test host/runner IDs, TEST_HOST, UUID UserDefaults suites, and UUID fixture Keychain services.\n'
