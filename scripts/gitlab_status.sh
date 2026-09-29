#!/usr/bin/env bash
# Post GitLab commit status for Codemagic MR builds (running|success|fail).
# Required: GITLAB_HOST, GITLAB_PROJECT_PATH, GITLAB_STATUS_CONTEXT,
#           GITLAB_TOKEN, CM_COMMIT, CM_PULL_REQUEST=true
# Optional: CM_BRANCH, CM_BUILD_ID, CM_PULL_REQUEST_NUMBER

set -euo pipefail

log() {
  echo "[gitlab-mr-status] $*" >&2
}

require_env() {
  : "${GITLAB_HOST:?GITLAB_HOST manquant}"
  : "${GITLAB_PROJECT_PATH:?GITLAB_PROJECT_PATH manquant}"
  : "${GITLAB_STATUS_CONTEXT:?GITLAB_STATUS_CONTEXT manquant}"
  : "${GITLAB_TOKEN:?GITLAB_TOKEN manquant}"
  : "${CM_COMMIT:?CM_COMMIT manquant}"
}

post_status() {
  local state="$1" description="$2" ok_msg="$3"

  local repo encoded
  repo="${GITLAB_PROJECT_PATH}"
  encoded="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$repo")"

  local body_file http_code
  body_file="$(mktemp)"
  http_code="$(
    curl -sS --path-as-is -o "$body_file" -w "%{http_code}" \
      --request POST \
      --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      --header "Content-Type: application/x-www-form-urlencoded" \
      --data "state=${state}" \
      --data "context=${GITLAB_STATUS_CONTEXT}" \
      --data "description=${description}" \
      --data "target_url=https://codemagic.io/build/${CM_BUILD_ID:-}" \
      $( [ -n "${CM_BRANCH:-}" ] && printf '%s' "--data ref=${CM_BRANCH}" ) \
      "${GITLAB_HOST}/projects/${encoded}/statuses/${CM_COMMIT}" || echo "000"
  )"

  if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    local mr_label=""
    [ -n "${CM_PULL_REQUEST_NUMBER:-}" ] && mr_label="MR !${CM_PULL_REQUEST_NUMBER} — "
    log "✓ ${mr_label}${ok_msg} (commit ${CM_COMMIT:0:8}, ref ${CM_BRANCH:-?})"
    rm -f "$body_file"
    return 0
  fi

  log "✗ Échec mise à jour GitLab (HTTP ${http_code})"
  cat "$body_file" >&2
  rm -f "$body_file"
  return 1
}

[ "${CM_PULL_REQUEST:-false}" = "true" ] || exit 0

require_env

case "${1:-}" in
  running) post_status "running" "Build en cours" "Status GitLab → en cours" ;;
  success) post_status "success" "Build réussi" "Status GitLab → OK" ;;
  fail)    post_status "failed" "Build échoué" "Status GitLab → échec" ;;
  *) echo "Usage: $0 running|success|fail" >&2; exit 1 ;;
esac
