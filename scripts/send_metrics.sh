#!/usr/bin/env bash
# Publishes the SonarQube analysis of the current sources and of the existing
# coverage/lcov.info. Usually run through `test.sh --sonar`, which runs the tests
# with coverage first. Run by the send_metrics lane.
#
# Usage (from any directory): bash fastlane/forge/scripts/send_metrics.sh
#
# Static settings (project key, sources, exclusions, lcov path) are read by
# sonar-scanner from the project's sonar-project.properties. sonar.projectVersion is
# passed from APP_BUILD_NAME (see common.sh).
#
# Settings (environment):
#   SONAR_TOKEN         SonarQube token (required)
#   SONAR_HOST_URL      SonarQube URL
#   SONAR_SCANNER_ARGS  extra sonar-scanner arguments (CI: branch / merge request analysis).
#                       When unset outside CI, the current Git branch is analysed.

set -euo pipefail
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

if [[ -z "${SONAR_TOKEN:-}" ]]; then
  forge_log "ERROR: SONAR_TOKEN is not set"
  exit 1
fi
if ! command -v sonar-scanner > /dev/null; then
  forge_log "ERROR: sonar-scanner not found: install it (e.g. brew install sonar-scanner)"
  exit 1
fi
if [[ ! -f coverage/lcov.info ]]; then
  forge_log "WARNING: coverage/lcov.info not found: the analysis will have no coverage"
fi

args=()
read -ra args <<< "${SONAR_SCANNER_ARGS:-}"
if [[ ${#args[@]} -eq 0 ]] && ! forge_is_ci; then
  args=("-Dsonar.branch.name=$(git rev-parse --abbrev-ref HEAD)")
fi
# Version of the analysis: the resolved app version, so that sonar-project.properties
# does not have to be bumped at each release
if [[ -n "${APP_BUILD_NAME:-}" && "${SONAR_SCANNER_ARGS:-}" != *sonar.projectVersion* ]]; then
  args+=("-Dsonar.projectVersion=$APP_BUILD_NAME")
fi

forge_log "Running SonarQube analysis..."
sonar-scanner ${args[@]+"${args[@]}"}
forge_log "SonarQube analysis published"
