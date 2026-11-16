#!/usr/bin/env bash
# Prints the folder of the sonar-scanner CLI, installing it first when the image does
# not provide it. Run by the .forge_test_sonar and .forge_checks GitLab jobs, which add
# the printed folder to the PATH:
#
#   export PATH="$(bash fastlane/forge/scripts/install_sonar_scanner.sh):${PATH}"
#
# Usage (from any directory): bash fastlane/forge/scripts/install_sonar_scanner.sh
#
# Settings (environment, set by the forge jobs):
#   FORGE_SONAR_SCANNER_VERSION  sonar-scanner CLI version
#   FORGE_SONAR_SCANNER_SHA256   SHA-256 of its linux-x64 zip (change both together)
#
# Locally, install it once instead (brew install sonar-scanner): the archive below is
# the Linux build, so the script refuses to install it on another system.

set -euo pipefail

# Logs go to stderr: stdout carries the folder the caller adds to the PATH.
if command -v sonar-scanner > /dev/null; then
  dirname "$(command -v sonar-scanner)"
  exit 0
fi

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "[forge] ERROR: sonar-scanner is not installed: install it (brew install sonar-scanner)" >&2
  exit 1
fi

VERSION="${FORGE_SONAR_SCANNER_VERSION:?FORGE_SONAR_SCANNER_VERSION is not set}"
SHA256="${FORGE_SONAR_SCANNER_SHA256:?FORGE_SONAR_SCANNER_SHA256 is not set}"

INSTALL_DIR="/opt/sonar-scanner-${VERSION}-linux-x64"

# stdout carries only the folder: the whole installation talks on stderr, so that
# nothing else (a checksum line, a tool banner) ends up in the caller's PATH.
{
  echo "[forge] Installing sonar-scanner ${VERSION}..."
  if ! command -v unzip > /dev/null; then
    apt-get update -qq
    apt-get install -y -qq unzip > /dev/null
  fi
  curl -sSLo /tmp/sonar-scanner.zip "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${VERSION}-linux-x64.zip"
  echo "${SHA256}  /tmp/sonar-scanner.zip" | sha256sum -c -
  unzip -q /tmp/sonar-scanner.zip -d /opt
  echo "[forge] sonar-scanner installed in ${INSTALL_DIR}"
} 1>&2

echo "${INSTALL_DIR}/bin"
