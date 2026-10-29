#!/usr/bin/env bash
# Flutter tests: prepare.sh, then flutter test. Run by the test lane and by the
# GitLab .forge_test_sonar job, without Ruby.
#
# Usage (from any directory): bash fastlane/forge/scripts/test.sh [--coverage] [--sonar]
#   --coverage  generates coverage/lcov.info and the HTML reports (coverage_report.sh)
#   --sonar     coverage, then the SonarQube analysis (send_metrics.sh). SONAR_TOKEN is
#               checked before the tests run: when it is missing, the analysis is
#               skipped locally and the script fails in CI.
#
# Settings (environment or fastlane/.env.* files, see common.sh):
#   FORGE_COVERAGE_EXCLUDES  space-separated lcov patterns excluded from the filtered report

set -euo pipefail

coverage=false
sonar=false
for arg in "$@"; do
  case "$arg" in
    --coverage) coverage=true ;;
    --sonar) sonar=true ;;
    *)
      echo "Usage: $0 [--coverage] [--sonar]" >&2
      exit 1
      ;;
  esac
done

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Checked before the tests so that a missing token does not fail after a full test run
if [[ "$sonar" == true ]]; then
  if [[ -z "${SONAR_TOKEN:-}" ]]; then
    forge_missing "SONAR_TOKEN is not set: the metrics will not be sent to SonarQube"
    sonar=false
  else
    coverage=true
  fi
fi

bash "$FORGE_SCRIPTS_DIR/prepare.sh"

if [[ -d test ]]; then
  forge_log "Running Flutter tests..."
  if [[ "$coverage" == true ]]; then
    fvm flutter test --coverage
  else
    fvm flutter test
  fi
  forge_log "Flutter tests passed"

  if [[ "$coverage" == true ]]; then
    forge_log "Generating coverage reports..."
    bash "$FORGE_SCRIPTS_DIR/coverage_report.sh"
  fi
else
  # flutter test fails without a test/ folder: SonarQube still gets the analysis, without coverage
  forge_log "No test/ folder: tests skipped"
fi

if [[ "$sonar" == true ]]; then
  bash "$FORGE_SCRIPTS_DIR/send_metrics.sh"
fi
