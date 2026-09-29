#!/usr/bin/env bash
# Generate coverage reports from coverage/lcov.info (produced by `flutter test --coverage`).
# Must be run from the Flutter project root (the `test` lane does it with coverage:true).
#
# Requires lcov: installed automatically when missing (Homebrew on macOS, apt-get on Linux).
#
# Optional: FORGE_COVERAGE_EXCLUDES  space-separated lcov patterns removed from the
#           filtered report (e.g. "lib/main.dart lib/pages/*")
#
# Output (coverage/):
#   lcov_filtered.info   filtered data (only when FORGE_COVERAGE_EXCLUDES is set)
#   html/                full HTML report
#   html_filtered/       filtered HTML report (only when FORGE_COVERAGE_EXCLUDES is set)
#   coverage_html.zip    HTML reports zipped (CI artifact)

set -euo pipefail
# Keep the lcov patterns unexpanded by the shell
set -f

log() {
  echo "[coverage-report] $*" >&2
}

LCOV_FILE="coverage/lcov.info"
FILTERED_FILE="coverage/lcov_filtered.info"

install_lcov() {
  if command -v brew >/dev/null; then
    log "lcov introuvable, installation via Homebrew..."
    brew install lcov
  elif command -v apt-get >/dev/null; then
    log "lcov introuvable, installation via apt-get..."
    local sudo=""
    [ "$(id -u)" -ne 0 ] && sudo="sudo"
    $sudo apt-get update -qq
    $sudo apt-get install -y -qq lcov
  else
    log "lcov introuvable et aucun gestionnaire de paquets supporté (brew, apt-get) : l'installer manuellement"
    exit 1
  fi
}

if ! command -v lcov >/dev/null || ! command -v genhtml >/dev/null; then
  install_lcov
fi
[ -f "$LCOV_FILE" ] || { log "$LCOV_FILE introuvable : lancer les tests avec --coverage"; exit 1; }

# lcov 2.x fails on patterns matching no file unless told otherwise
LCOV_EXTRA_ARGS=()
if lcov --version | grep -Eq 'version (2|[3-9])\.'; then
  LCOV_EXTRA_ARGS+=(--ignore-errors unused)
fi

rm -rf coverage/html coverage/html_filtered coverage/coverage_html.zip "$FILTERED_FILE"

log "Génération du rapport HTML complet..."
genhtml -q "$LCOV_FILE" -o coverage/html
html_dirs=(html)

if [ -n "${FORGE_COVERAGE_EXCLUDES:-}" ]; then
  log "Filtrage : ${FORGE_COVERAGE_EXCLUDES}"
  # shellcheck disable=SC2086
  lcov --remove "$LCOV_FILE" ${FORGE_COVERAGE_EXCLUDES} ${LCOV_EXTRA_ARGS[@]+"${LCOV_EXTRA_ARGS[@]}"} -o "$FILTERED_FILE" >/dev/null
  genhtml -q "$FILTERED_FILE" -o coverage/html_filtered
  html_dirs+=(html_filtered)
fi

(cd coverage && zip -qr coverage_html.zip "${html_dirs[@]}")

echo ""
echo "Couverture globale :"
lcov --summary "$LCOV_FILE"

if [ -f "$FILTERED_FILE" ]; then
  echo ""
  echo "Couverture filtrée :"
  lcov --summary "$FILTERED_FILE"
fi

echo ""
log "Rapports générés dans coverage/html$([ -f "$FILTERED_FILE" ] && echo " et coverage/html_filtered")"
