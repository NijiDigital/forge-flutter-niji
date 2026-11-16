#!/usr/bin/env bash
# Prints APP_BUILD_NAME and APP_BUILD_NUMBER, resolved by common.sh, as KEY=VALUE lines.
# Read by the version_metadata lane.
#
# Usage (from any directory): bash fastlane/forge/scripts/version.sh

set -euo pipefail
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

echo "APP_BUILD_NAME=${APP_BUILD_NAME:-}"
echo "APP_BUILD_NUMBER=$APP_BUILD_NUMBER"
