#!/usr/bin/env bash
# Flutter static analysis: prepare.sh, then flutter analyze. Run by the analyze lane
# and by the GitLab .forge_analyze job, without Ruby.
#
# Usage (from any directory): bash fastlane/forge/scripts/analyze.sh
#
# Settings (environment or fastlane/.env.* files, see common.sh):
#   FORGE_ANALYZE_ARGS  extra flutter analyze arguments (e.g. --no-fatal-infos)

set -euo pipefail
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

bash "$FORGE_SCRIPTS_DIR/prepare.sh"

forge_log "Running Flutter analyze..."
# shellcheck disable=SC2086
fvm flutter analyze ${FORGE_ANALYZE_ARGS:-}
forge_log "Flutter analyze passed"
