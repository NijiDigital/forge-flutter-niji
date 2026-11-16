#!/usr/bin/env bash
# Publishes the SonarQube analysis of the current sources and of the existing
# coverage/lcov.info. Usually run through `test.sh --sonar`, which runs the tests
# with coverage first. Run by the send_metrics lane.
#
# Usage (from any directory): bash fastlane/forge/scripts/send_metrics.sh
#
# The whole SonarQube configuration lives in the project's sonar-project.properties:
# key, sources, exclusions, lcov path, and the per-run values read from the environment
# with ${env.VAR} (version, branch, merge request). No sonar-scanner argument is passed.
#
# Settings (environment):
#   SONAR_TOKEN         SonarQube token (required)
#   SONAR_HOST_URL      SonarQube URL (or sonar.host.url in sonar-project.properties)
#
# Exported for sonar-project.properties:
#   APP_BUILD_NAME      analysis version, ${env.APP_BUILD_NAME} (see common.sh)
#   FORGE_SONAR_BRANCH  branch to analyse, ${env.FORGE_SONAR_BRANCH}: CI_COMMIT_BRANCH on
#                       CI (empty in merge request and tag pipelines), the current Git
#                       branch locally. Kept when already set.

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

# Merge request pipelines: sonar.pullrequest.* read the GitLab CI_MERGE_REQUEST_*
# variables directly. Branch pipelines and local runs: sonar.branch.name reads
# FORGE_SONAR_BRANCH.
if [[ -z "${FORGE_SONAR_BRANCH+set}" ]]; then
  if forge_is_ci; then
    export FORGE_SONAR_BRANCH="${CI_COMMIT_BRANCH:-}"
  else
    FORGE_SONAR_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    export FORGE_SONAR_BRANCH
  fi
fi
if ! grep -q 'env\.FORGE_SONAR_BRANCH' sonar-project.properties 2>/dev/null; then
  forge_log "WARNING: sonar-project.properties does not read \${env.FORGE_SONAR_BRANCH}: branch and merge request analyses are disabled (see the forge README)"
fi

forge_log "Running SonarQube analysis..."
sonar-scanner
forge_log "SonarQube analysis published"
