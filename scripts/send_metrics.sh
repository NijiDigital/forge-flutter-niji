#!/usr/bin/env bash
# Publishes the SonarQube analysis of the current sources and of the existing
# coverage/lcov.info. Usually run through `test.sh --sonar`, which runs the tests
# with coverage first. Run by the send_metrics lane.
#
# Usage (from any directory): bash fastlane/forge/scripts/send_metrics.sh
#
# The static SonarQube configuration (key, sources, exclusions, lcov path, version)
# lives in the project's sonar-project.properties. The analysis target is decided
# here and passed as scanner arguments: a merge request when the pipeline is one, the
# branch otherwise. The project file must not declare sonar.branch.name or
# sonar.pullrequest.*: declaring both makes SonarQube run a branch analysis, even when
# sonar.branch.name is empty.
#
# Settings (environment):
#   SONAR_TOKEN         SonarQube token (required)
#   SONAR_HOST_URL      SonarQube URL (or sonar.host.url in sonar-project.properties)
#   FORGE_SONAR_BRANCH  branch analysed outside a merge request: CI_COMMIT_BRANCH on CI,
#                       the current Git branch locally. Kept when already set.

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

scanner_args=()

if [[ -n "${CI_MERGE_REQUEST_IID:-}" ]]; then
  forge_log "Analysis target: merge request !${CI_MERGE_REQUEST_IID}"
  scanner_args+=("-Dsonar.pullrequest.key=${CI_MERGE_REQUEST_IID}")
  scanner_args+=("-Dsonar.pullrequest.branch=${CI_MERGE_REQUEST_SOURCE_BRANCH_NAME:-}")
  scanner_args+=("-Dsonar.pullrequest.base=${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}")
else
  if [[ -z "${FORGE_SONAR_BRANCH+set}" ]]; then
    if forge_is_ci; then
      export FORGE_SONAR_BRANCH="${CI_COMMIT_BRANCH:-}"
    else
      FORGE_SONAR_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
      export FORGE_SONAR_BRANCH
    fi
  fi
  if [[ -n "${FORGE_SONAR_BRANCH:-}" ]]; then
    forge_log "Analysis target: branch ${FORGE_SONAR_BRANCH}"
    scanner_args+=("-Dsonar.branch.name=${FORGE_SONAR_BRANCH}")
  else
    forge_log "Analysis target: default branch"
  fi
fi

# Guard: the project file must stay free of the analysis target properties.
if grep -qE '^[[:space:]]*sonar\.(branch\.name|pullrequest\.)' sonar-project.properties 2>/dev/null; then
  forge_log "WARNING: sonar-project.properties declares sonar.branch.name or sonar.pullrequest.*:"
  forge_log "WARNING: remove these lines, the forge passes them (see the forge README)"
fi

forge_log "Running SonarQube analysis..."
sonar-scanner ${scanner_args[@]+"${scanner_args[@]}"}
forge_log "SonarQube analysis published"
