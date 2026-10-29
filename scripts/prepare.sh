#!/usr/bin/env bash
# Prepares the project before analyzing, testing or building it: CI files, project
# script, pub get, build_runner. Run by analyze.sh, test.sh and the prepare lane.
#
# Usage (from any directory): bash fastlane/forge/scripts/prepare.sh
#
# Settings (environment or fastlane/.env.* files, see common.sh):
#   FORGE_CI_FILES           files written from environment variables, space-separated
#                            VAR:path entries (VAR?:path: optional variable)
#   FORGE_PLATFORM           android or ios: also writes FORGE_<PLATFORM>_CI_FILES
#                            (set by the platform lanes)
#   FORGE_PREPARE_SCRIPT     project script run (with bash) after the files are written
#   FORGE_BUILD_RUNNER       true runs build_runner after pub get (default: false)

set -euo pipefail
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

forge_log "Version: ${APP_BUILD_NAME:-} ($APP_BUILD_NUMBER)"

# Writes files from environment variables (CI secrets), path relative to the project
# root. A missing variable leaves the existing file untouched.
write_ci_files() {
  local entries=() entry name path content
  read -ra entries <<< "$1"
  for entry in ${entries[@]+"${entries[@]}"}; do
    name="${entry%%:*}"
    path="${entry#*:}"
    if [[ "$entry" != *:* || -z "$name" || -z "$path" ]]; then
      forge_log "ERROR: Invalid CI file entry '$entry', expected VAR:path"
      exit 1
    fi

    if [[ "$name" == *\? ]]; then
      name="${name%\?}"
      [[ -n "${!name:-}" ]] || continue
    elif [[ -z "${!name:-}" ]]; then
      forge_missing "$name is not set: $path not written"
      continue
    fi

    content="${!name}"
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "${content%$'\n'}" > "$path"
    forge_log "Wrote $path from $name"
  done
}

write_ci_files "${FORGE_CI_FILES:-}"
if [[ -n "${FORGE_PLATFORM:-}" ]]; then
  platform_files="FORGE_$(echo "$FORGE_PLATFORM" | tr '[:lower:]' '[:upper:]')_CI_FILES"
  write_ci_files "${!platform_files:-}"
fi

if [[ -n "${FORGE_PREPARE_SCRIPT:-}" ]]; then
  forge_log "Running $FORGE_PREPARE_SCRIPT..."
  bash "$FORGE_PREPARE_SCRIPT"
fi

forge_log "Fetching Flutter dependencies..."
fvm flutter pub get

if forge_bool "${FORGE_BUILD_RUNNER:-}" false; then
  forge_log "Running build_runner..."
  fvm dart run build_runner build --delete-conflicting-outputs
fi
