#!/usr/bin/env bash
set -euo pipefail

readonly PREFERRED_SIMULATOR_ID="${AURALYST_SIMULATOR_ID:-86A1B10E-ED24-44E3-ABA2-A63D65D10832}"
readonly DERIVED_DATA_PATH="${AURALYST_DERIVED_DATA_PATH:-/tmp/AuralystAppUITestsDerivedData}"
readonly RESULT_BUNDLE_PATH="${AURALYST_UI_TEST_RESULT_BUNDLE:-/tmp/AuralystAppUITests.xcresult}"
readonly XCODEBUILD_QUIET="${AURALYST_XCODEBUILD_QUIET:-0}"
readonly APP_BUNDLE_ID="com.ryanleewilliams.AuralystApp"

resolve_destination() {
  local detected_destination

  detected_destination=$(
    xcrun simctl list devices available -j | python3 -c '
import json
import sys

preferred_id = sys.argv[1]
data = json.load(sys.stdin)
fallback_name = None
fallback_udid = None

for runtime, devices in data["devices"].items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if not device.get("isAvailable"):
            continue
        if device.get("udid") == preferred_id:
            print(f"{preferred_id}|platform=iOS Simulator,id={preferred_id}")
            raise SystemExit(0)
        if fallback_name is None and "iPhone" in device.get("name", ""):
            fallback_name = device["name"]
            fallback_udid = device["udid"]

if fallback_name is None or fallback_udid is None:
    raise SystemExit("No available iPhone simulator found.")

print(f"{fallback_udid}|platform=iOS Simulator,name={fallback_name}")
' "${PREFERRED_SIMULATOR_ID}"
  )

  printf '%s\n' "${detected_destination}"
}

boot_simulator() {
  local simulator_udid="$1"

  xcrun simctl boot "${simulator_udid}" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "${simulator_udid}" -b
}

build_xcode_command() {
  local destination="$1"
  local -a command=(
    xcodebuild
    test
    -project AuralystApp.xcodeproj
    -scheme AuralystApp
    -destination "${destination}"
    -derivedDataPath "${DERIVED_DATA_PATH}"
    -only-testing:AuralystAppUITests
    -resultBundlePath "${RESULT_BUNDLE_PATH}"
    -skipPackagePluginValidation
    CODE_SIGN_IDENTITY=-
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGNING_ALLOWED=NO
    ENABLE_USER_SCRIPT_SANDBOXING=NO
    SWIFT_ENABLE_EXPERIMENTAL_FEATURES=Macros
    "OTHER_SWIFT_FLAGS=\$(inherited) -enable-experimental-feature Macros -enable-experimental-feature CompilerPlugin"
  )

  if [[ "${XCODEBUILD_QUIET}" == "1" ]]; then
    command+=(-quiet)
  fi

  printf '%s\0' "${command[@]}"
}

run_xcodebuild() {
  local destination="$1"
  local -a command=()

  while IFS= read -r -d '' arg; do
    command+=("${arg}")
  done < <(build_xcode_command "${destination}")

  "${command[@]}"
}

main() {
  local resolved_destination
  local destination
  local simulator_udid

  resolved_destination="$(resolve_destination)"
  simulator_udid="${resolved_destination%%|*}"
  destination="${resolved_destination#*|}"

  rm -rf "${RESULT_BUNDLE_PATH}"
  mkdir -p "${DERIVED_DATA_PATH}"
  mkdir -p "$(dirname "${RESULT_BUNDLE_PATH}")"

  echo "Booting simulator: ${simulator_udid}"
  boot_simulator "${simulator_udid}"

  # Remove stale app data so eraseDatabaseOnSchemaChange can VACUUM
  # without interference from the ATTACHed metadata database.
  echo "Uninstalling previous app data…"
  xcrun simctl uninstall "${simulator_udid}" "${APP_BUNDLE_ID}" 2>/dev/null || true

  echo "Running UI tests with destination: ${destination}"
  echo "DerivedData: ${DERIVED_DATA_PATH}"
  echo "Result bundle: ${RESULT_BUNDLE_PATH}"

  echo "Running UI tests..."
  run_xcodebuild "${destination}"

  echo "UI tests passed."
}

main "$@"
