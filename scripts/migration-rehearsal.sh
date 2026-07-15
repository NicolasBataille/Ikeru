#!/bin/bash
# migration-rehearsal.sh — end-to-end pre-release gate for the SwiftData
# staged-migration bug (see IkeruCore/Sources/Models/Schema/IkeruSchema.swift).
#
# What it does:
#   1. Builds the last RELEASED commit (default a7371a3 — the pre-versioned-
#      schema on-disk shape) for a dedicated simulator, boots/erases that
#      simulator, installs the released build, launches it with
#      -skipOnboarding (auto-creates a default profile so a real RPGState/
#      Card/UserProfile store gets written to disk), waits, then terminates
#      it — this fabricates a genuine "legacy" on-device store.
#   2. Builds the CURRENT checkout (this repo's working tree, i.e. the fix),
#      installs it OVER the released build without erasing the simulator
#      (an in-place upgrade install, exactly like a real TestFlight/App
#      Store update), and launches it.
#   3. Scans the simulator's unified log for the failure signatures of the
#      bug this script exists to catch — `loadIssueModelContainer`, "unknown
#      model version", "Failed to create ModelContainer" — and checks the
#      app process is still alive. Exits non-zero on either.
#
# Usage: scripts/migration-rehearsal.sh [base-commit]
#   base-commit defaults to a7371a3 (the last commit before IkeruSchemaV1
#   existed, i.e. the actual on-disk shape every real TestFlight install
#   upgrades FROM).
#
# NEVER point SIM_ID at the plain "iPhone 17" simulator — that runtime image
# is corrupted on this machine. Always use the "iPhone 17e" simulator below.

set -euo pipefail

BASE_COMMIT="${1:-a7371a3}"
SIM_ID="BAD71E17-02EA-4987-AA2F-0D750123DD14" # iPhone 17e — NEVER "iPhone 17"
BUNDLE_ID="com.ikeru.app"
SCHEME="Ikeru"
PROJECT_FILE="Ikeru.xcodeproj"
LAUNCH_SETTLE_SECONDS=15

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

WORK_DIR="$(mktemp -d)"
BASE_WORKTREE="$WORK_DIR/released-checkout"
WORKTREE_ADDED=0

cleanup() {
    if [ "$WORKTREE_ADDED" -eq 1 ]; then
        git worktree remove --force "$BASE_WORKTREE" 2>/dev/null || true
        git worktree prune 2>/dev/null || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "=== Migration rehearsal: $BASE_COMMIT -> $(git rev-parse --short HEAD) on simulator $SIM_ID ==="

# --- 1. Build the released commit in an isolated worktree -----------------

echo "--- Checking out released commit $BASE_COMMIT into a scratch worktree"
git worktree add --detach "$BASE_WORKTREE" "$BASE_COMMIT" >/dev/null
WORKTREE_ADDED=1

echo "--- Building released commit $BASE_COMMIT for the simulator"
BASE_DERIVED_DATA="$WORK_DIR/derived-base"
# -configuration Debug is LOAD-BEARING: the Debug build keeps fatalError on
# migration failure, so a dead process = failed migration. Release builds
# silently recover (store moved aside + fresh start), which would make the
# process-alive check a false PASS.
xcodebuild build -configuration Debug \
    -project "$BASE_WORKTREE/$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -destination "id=$SIM_ID" \
    -derivedDataPath "$BASE_DERIVED_DATA" \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO

BASE_APP_PATH="$(find "$BASE_DERIVED_DATA/Build/Products" -maxdepth 2 -name "Ikeru.app" -print -quit)"
if [ -z "$BASE_APP_PATH" ]; then
    echo "FAIL: could not find built Ikeru.app for released commit $BASE_COMMIT"
    exit 1
fi

# --- 2. Boot a clean simulator and install the released build --------------

echo "--- Booting and erasing simulator $SIM_ID"
xcrun simctl shutdown "$SIM_ID" >/dev/null 2>&1 || true
xcrun simctl erase "$SIM_ID"
xcrun simctl boot "$SIM_ID"
xcrun simctl bootstatus "$SIM_ID" -b

echo "--- Installing and launching the RELEASED build ($BASE_COMMIT)"
xcrun simctl install "$SIM_ID" "$BASE_APP_PATH"
LOG_START="$(date "+%Y-%m-%d %H:%M:%S")"
xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" -skipOnboarding

echo "--- Waiting ${LAUNCH_SETTLE_SECONDS}s for the released build to create its on-disk store"
sleep "$LAUNCH_SETTLE_SECONDS"

echo "--- Terminating the released build"
xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true

# --- 3. Build current HEAD and upgrade-install over the legacy store -------

echo "--- Building current HEAD for the simulator"
HEAD_DERIVED_DATA="$WORK_DIR/derived-head"
# -configuration Debug is LOAD-BEARING: the Debug build keeps fatalError on
# migration failure, so a dead process = failed migration. Release builds
# silently recover (store moved aside + fresh start), which would make the
# process-alive check a false PASS.
xcodebuild build -configuration Debug \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -destination "id=$SIM_ID" \
    -derivedDataPath "$HEAD_DERIVED_DATA" \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO

HEAD_APP_PATH="$(find "$HEAD_DERIVED_DATA/Build/Products" -maxdepth 2 -name "Ikeru.app" -print -quit)"
if [ -z "$HEAD_APP_PATH" ]; then
    echo "FAIL: could not find built Ikeru.app for current HEAD"
    exit 1
fi

echo "--- Installing (upgrade, no erase) and launching current HEAD"
xcrun simctl install "$SIM_ID" "$HEAD_APP_PATH"
xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" -skipOnboarding

echo "--- Waiting ${LAUNCH_SETTLE_SECONDS}s for the staged migration to run"
sleep "$LAUNCH_SETTLE_SECONDS"

PROCESS_ALIVE=0
if xcrun simctl spawn "$SIM_ID" launchctl list 2>/dev/null | grep -q "$BUNDLE_ID"; then
    PROCESS_ALIVE=1
fi

xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true

# --- 4. Scan the device log for the migration-failure signatures -----------

echo "--- Scanning device log for migration-failure signatures"
LOG_OUTPUT="$(xcrun simctl spawn "$SIM_ID" log show \
    --predicate 'processImagePath CONTAINS "Ikeru"' \
    --style compact \
    --start "$LOG_START" 2>/dev/null || true)"

FAILURE=0

if echo "$LOG_OUTPUT" | grep -qE "loadIssueModelContainer|unknown model version|Failed to create ModelContainer"; then
    echo "FAIL: migration-failure signature found in device log:"
    echo "$LOG_OUTPUT" | grep -E "loadIssueModelContainer|unknown model version|Failed to create ModelContainer"
    FAILURE=1
fi

if [ "$PROCESS_ALIVE" -eq 0 ]; then
    echo "FAIL: current HEAD's app process was not running after the upgrade launch (it likely crashed)"
    FAILURE=1
fi

if [ "$FAILURE" -ne 0 ]; then
    echo "=== MIGRATION REHEARSAL FAILED ==="
    exit 1
fi

echo "=== MIGRATION REHEARSAL PASSED ==="
exit 0
