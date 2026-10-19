#!/bin/sh
set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
    printf 'Usage: %s <build-derived-data-dir> <destination-specifier> [execution-work-dir] [all|crew-contracts|c36-ui|crew-edit-ui|crew-info-ui]\n' "$0" >&2
    exit 2
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_derived_data=$(mkdir -p "$1" && CDPATH= cd -- "$1" && pwd -P)
destination=$2
execution_work_dir_arg=${3-}
test_selection=${4:-all}
developer_dir=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
xcodebuild="$developer_dir/usr/bin/xcodebuild"
products_dir="$build_derived_data/Build/Products/Debug-iphonesimulator"

test -x "$xcodebuild" || {
    printf 'xcodebuild is unavailable: %s\n' "$xcodebuild" >&2
    exit 1
}

# Derive TEST_HOST from the built host plist and reject product-app artifacts
# while inspecting the isolated host, runner, test-bundle plists, and .xctestrun.
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

# Keep run outputs in a fresh path separate from the build-for-testing inputs.
if [ -n "$execution_work_dir_arg" ]; then
    mkdir -p "$execution_work_dir_arg"
    execution_work_dir=$(CDPATH= cd -- "$execution_work_dir_arg" && pwd -P)
else
    execution_work_dir=$(mktemp -d "${TMPDIR:-/tmp}/mov-isolated-ui-run.XXXXXX")
fi
case "$execution_work_dir/" in
    "$build_derived_data/"*)
        printf 'Execution work directory must be separate from build-for-testing DerivedData: %s\n' "$execution_work_dir" >&2
        exit 1
        ;;
esac
derived_data_path="$execution_work_dir/DerivedData"
result_bundle="$execution_work_dir/FocusedUITests.xcresult"
test ! -e "$derived_data_path" || {
    printf 'Run DerivedData path already exists; choose a fresh execution work directory: %s\n' "$derived_data_path" >&2
    exit 1
}
test ! -e "$result_bundle" || {
    printf 'Result bundle already exists; choose a fresh execution work directory: %s\n' "$result_bundle" >&2
    exit 1
}
mkdir -p "$derived_data_path"
printf 'UI-test run DerivedData: %s\nUI-test result bundle: %s\n' "$derived_data_path" "$result_bundle"

case "$test_selection" in
    all) ;;
    crew-contracts)
        "$xcodebuild" test-without-building -xctestrun "$xctestrun" \
            -destination "$destination" -parallel-testing-enabled NO \
            -derivedDataPath "$derived_data_path" -resultBundlePath "$result_bundle" \
            -only-testing:MovTests/ThemeTests/testCrewManagementClientUsesOnlyConfirmedControllerRoutesAndDTOs \
            -only-testing:MovTests/ThemeTests/testCrewManagementClientRejectsUnconfirmedRoleAndNonNumericIDsBeforeSending \
            -only-testing:MovTests/ThemeTests/testCrewPostEditAndDeleteUseConfirmedControllerRoutes \
            -only-testing:MovTests/ThemeTests/testCrewPostMutationsRejectNoncanonicalIDsAndUnknownEditResponses \
            -only-testing:MovTests/WireframeCrewGuidanceFlowTests/testGuidanceSaveRefreshesAndPreservesLatestCrewNameAndIntroduction \
            -only-testing:MovTests/WireframeCrewGuidanceFlowTests/testGuidanceSaveRecoversLostPutResponseByReadingBeforeRetry \
            -only-testing:MovTests/WireframeCrewGuidanceFlowTests/testOrdinaryCrewMemberCannotSaveGuidance
        exit $?
        ;;
    c36-ui)
        "$xcodebuild" test-without-building -xctestrun "$xctestrun" \
            -destination "$destination" -parallel-testing-enabled NO \
            -derivedDataPath "$derived_data_path" -resultBundlePath "$result_bundle" \
            -only-testing:MovUITests/LaunchTests/testRemoteCrewJoinGuideSaveUsesManagerOnlyC36AndPersistsServerValue
        exit $?
        ;;
    crew-edit-ui)
        "$xcodebuild" test-without-building -xctestrun "$xctestrun" \
            -destination "$destination" -parallel-testing-enabled NO \
            -derivedDataPath "$derived_data_path" -resultBundlePath "$result_bundle" \
            -only-testing:MovUITests/LaunchTests/testRemoteCrewInformationEditRequiresManagerAndDiscardsDirtyDraft \
            -only-testing:MovUITests/LaunchTests/testRemoteCrewJoinGuideSaveUsesManagerOnlyC36AndPersistsServerValue
        exit $?
        ;;
    crew-info-ui)
        "$xcodebuild" test-without-building -xctestrun "$xctestrun" \
            -destination "$destination" -parallel-testing-enabled NO \
            -derivedDataPath "$derived_data_path" -resultBundlePath "$result_bundle" \
            -only-testing:MovUITests/LaunchTests/testRemoteCrewInformationEditRequiresManagerAndDiscardsDirtyDraft
        exit $?
        ;;
    *)
        printf 'Unknown test selection: %s\n' "$test_selection" >&2
        exit 2
        ;;
esac

# Run only the focused UI cases. This wrapper is the only supported entry point
# for test-without-building; it rechecks the real product/host/test artifacts on
# every invocation, directly before executing the tests.
"$xcodebuild" test-without-building -xctestrun "$xctestrun" \
    -destination "$destination" -parallel-testing-enabled NO \
    -derivedDataPath "$derived_data_path" -resultBundlePath "$result_bundle" \
    -only-testing:MovUITests/LaunchTests/testProfilePhotoUploadCanBeCancelledWithoutApplyingLateResult \
    -only-testing:MovUITests/LaunchTests/testProfilePhotoFailureIsVisibleAndLeavesEditorAvailable \
    -only-testing:MovUITests/LaunchTests/testShareOutputPNGCanBeAttachedToCommunityDraft \
    -only-testing:MovUITests/LaunchTests/testCommunityPublishBusyPreventsReturningToEditableComposer \
    -only-testing:MovUITests/LaunchTests/testCommunityAmbiguousCreateOffersExplicitRecoveryWithoutEditingPayload \
    -only-testing:MovUITests/LaunchTests/testRemoteCrewSearchApplyCancelEmptyStateAndCommunityTab \
    -only-testing:MovUITests/LaunchTests/testRemoteCrewApplicationUnknownOutcomeBlocksDuplicateRetry \
    -only-testing:MovUITests/LaunchTests/testRemoteCrewDirectoryCancelsSlowOldQueryAndDeduplicatesCursorPages \
    -only-testing:MovUITests/LaunchTests/testRemoteCrewPendingApplicationsPaginateRetryCancellationAndReentry \
    -only-testing:MovUITests/LaunchTests/testRemoteCrewInformationEditRequiresManagerAndDiscardsDirtyDraft \
    -only-testing:MovUITests/LaunchTests/testRemoteCrewJoinGuideSaveUsesManagerOnlyC36AndPersistsServerValue \
    -only-testing:MovUITests/LaunchTests/testRemoteCrewAccountSwitchDiscardsLateOldAccountListResponse \
    -only-testing:MovUITests/LaunchTests/testRemoteCrewCreateMembersAndBoardManagementUseConfirmedContracts \
    -only-testing:MovUITests/LaunchTests/testRemoteCrewBoardCapacityPreventsCreateAndRestoreAtFiveActive \
    -only-testing:MovUITests/LaunchTests/testRemoteCrewManagerCanApproveAndRejectAndMemberCannotReadQueue \
    -only-testing:MovUITests/LaunchTests/testRemoteCrewRequestStaysOnceWhenLeavingWhileInFlightAndBoardPostFlow \
    -only-testing:MovUITests/LaunchTests/testRemoteCrewPostAuthorCanEditRetryConflictAndDiscardDraft \
    -only-testing:MovUITests/LaunchTests/testRemoteCrewPostDeleteConfirmationRetryAndManagerPermissions \
    -only-testing:MovUITests/LaunchTests/testRemoteCrewPostActionsRespectAuthorAndRecruitmentModeratorPermissions \
    -only-testing:MovUITests/LaunchTests/testRemoteCrewPostMutationCanBeLeftAndAccountScopeSwitchDiscardsLateResult \
    -only-testing:MovUITests/LaunchTests/testRemoteCrewReadFailureCanBeRetried \
    -only-testing:MovTests/ThemeTests/testCrewManagementClientUsesOnlyConfirmedControllerRoutesAndDTOs \
    -only-testing:MovTests/ThemeTests/testCrewManagementClientRejectsUnconfirmedRoleAndNonNumericIDsBeforeSending \
    -only-testing:MovTests/ThemeTests/testCrewPostEditAndDeleteUseConfirmedControllerRoutes \
    -only-testing:MovTests/ThemeTests/testCrewPostMutationsRejectNoncanonicalIDsAndUnknownEditResponses \
    -only-testing:MovTests/WireframeCrewGuidanceFlowTests/testGuidanceSaveRefreshesAndPreservesLatestCrewNameAndIntroduction \
    -only-testing:MovTests/WireframeCrewGuidanceFlowTests/testGuidanceSaveRecoversLostPutResponseByReadingBeforeRetry \
    -only-testing:MovTests/WireframeCrewGuidanceFlowTests/testOrdinaryCrewMemberCannotSaveGuidance
