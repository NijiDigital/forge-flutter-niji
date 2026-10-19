#!/usr/bin/env bash
# Install and activate, with FVM, the Flutter version pinned in the project's .fvmrc.
#
# Usage (from any directory): bash fastlane/forge/scripts/setup_fvm.sh
#
# Requires dart on the PATH (Codemagic, cirruslabs/flutter images...).
# Optional:
#   FORGE_FVM_VERSION  FVM version to activate (default: latest)
#   FVM_CACHE_PATH     FVM cache folder (CI cache, e.g. $CI_PROJECT_DIR/.fvm-cache)
#
# On Codemagic, the Flutter SDK is added to the PATH of the next steps through $CM_ENV.
# Elsewhere, add <project>/.fvm/flutter_sdk/bin and the pub cache bin folder to the PATH.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f .fvmrc ]]; then
  echo "Missing .fvmrc in $ROOT_DIR" >&2
  exit 1
fi

FLUTTER_VERSION="$(sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .fvmrc | head -n 1)"
if [[ -z "$FLUTTER_VERSION" ]]; then
  echo "Could not read the Flutter version from .fvmrc" >&2
  exit 1
fi
echo "Installing Flutter $FLUTTER_VERSION from .fvmrc"

PUB_BIN="${PUB_CACHE:-$HOME/.pub-cache}/bin"
if [[ -n "${FORGE_FVM_VERSION:-}" ]]; then
  dart pub global activate fvm "$FORGE_FVM_VERSION"
else
  dart pub global activate fvm
fi
export PATH="$PATH:$PUB_BIN"

fvm install "$FLUTTER_VERSION"

# A restored CI cache can leave .fvm/flutter_sdk behind and block `fvm use`.
rm -rf .fvm/flutter_sdk

fvm use "$FLUTTER_VERSION" --force

if [[ -n "${CM_ENV:-}" ]]; then
  echo "PATH=$ROOT_DIR/.fvm/flutter_sdk/bin:$PATH" >> "$CM_ENV"
fi
fvm flutter --version
