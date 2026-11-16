#!/usr/bin/env sh
# Trigger a Codemagic workflow from GitLab CI through the Codemagic API, wait for it
# to complete and download its artefacts.
#
# Usage: fastlane/forge/scripts/codemagic_build.sh <workflowId> [artifacts_dir]
#
# Required (GitLab > Settings > CI/CD > Variables):
#   CODEMAGIC_API_TOKEN  Codemagic API token (masked)
#   CODEMAGIC_APP_ID     Codemagic application id (visible in the app URL)
# Optional:
#   CODEMAGIC_POLL_INTERVAL  polling interval in seconds (default: 30)
#
# Codemagic builds the HEAD of the pipeline branch (or tag) at trigger time, which may
# differ from the exact pipeline commit.
# The build id is written to .codemagic_build_id so the build can be canceled.

set -eu

WORKFLOW_ID="${1:?Usage: $0 <workflowId> [artifacts_dir]}"
ARTIFACTS_DIR="${2:-codemagic-artifacts}"
API="https://api.codemagic.io"
POLL_INTERVAL="${CODEMAGIC_POLL_INTERVAL:-30}"

: "${CODEMAGIC_API_TOKEN:?CODEMAGIC_API_TOKEN is not set}"
: "${CODEMAGIC_APP_ID:?CODEMAGIC_APP_ID is not set}"

api() {
  curl -sS --fail-with-body -H "x-auth-token: ${CODEMAGIC_API_TOKEN}" -H "Content-Type: application/json" "$@"
}

# Ref to build: tag, MR source branch, or pipeline branch
if [ -n "${CI_COMMIT_TAG:-}" ]; then
  REF_KEY="tag"
  REF_VALUE="${CI_COMMIT_TAG}"
else
  REF_KEY="branch"
  REF_VALUE="${CI_MERGE_REQUEST_SOURCE_BRANCH_NAME:-${CI_COMMIT_BRANCH:-${CI_COMMIT_REF_NAME}}}"
fi

PAYLOAD=$(jq -n \
  --arg appId "${CODEMAGIC_APP_ID}" \
  --arg workflowId "${WORKFLOW_ID}" \
  --arg refKey "${REF_KEY}" \
  --arg refValue "${REF_VALUE}" \
  --arg pipelineId "${CI_PIPELINE_ID:-}" \
  --arg pipelineUrl "${CI_PIPELINE_URL:-}" \
  --arg jobUrl "${CI_JOB_URL:-}" \
  --arg commitSha "${CI_COMMIT_SHA:-}" \
  '{
    appId: $appId,
    workflowId: $workflowId,
    ($refKey): $refValue,
    labels: ["gitlab", ("pipeline-" + $pipelineId)],
    environment: {
      variables: {
        GITLAB_PIPELINE_ID: $pipelineId,
        GITLAB_PIPELINE_URL: $pipelineUrl,
        GITLAB_JOB_URL: $jobUrl,
        GITLAB_COMMIT_SHA: $commitSha
      }
    }
  }')

echo "Triggering Codemagic workflow '${WORKFLOW_ID}' on ${REF_KEY} '${REF_VALUE}'..."
BUILD_ID=$(api -X POST "${API}/builds" -d "${PAYLOAD}" | jq -r '.buildId')
if [ -z "${BUILD_ID}" ] || [ "${BUILD_ID}" = "null" ]; then
  echo "Could not read the Codemagic build id." >&2
  exit 1
fi
echo "${BUILD_ID}" > .codemagic_build_id
echo "Codemagic build: https://codemagic.io/app/${CODEMAGIC_APP_ID}/build/${BUILD_ID}"

# Poll until the build reaches a terminal status
LAST_STATUS=""
while true; do
  BUILD_JSON=$(api "${API}/builds/${BUILD_ID}") || {
    echo "Could not read build status, retrying in ${POLL_INTERVAL}s..." >&2
    sleep "${POLL_INTERVAL}"
    continue
  }
  STATUS=$(printf '%s' "${BUILD_JSON}" | jq -r '.build.status')
  if [ "${STATUS}" != "${LAST_STATUS}" ]; then
    echo "$(date '+%H:%M:%S') status: ${STATUS}"
    LAST_STATUS="${STATUS}"
  fi
  case "${STATUS}" in
    finished|failed|canceled|timeout|skipped|warning) break ;;
  esac
  sleep "${POLL_INTERVAL}"
done

# Download artefacts (also on failure, when some were produced)
mkdir -p "${ARTIFACTS_DIR}"
printf '%s' "${BUILD_JSON}" | jq -r '.build.artefacts[]? | [.name, .url] | @tsv' |
  while IFS="$(printf '\t')" read -r NAME URL; do
    echo "Downloading ${NAME}..."
    curl -sS --fail -L -H "x-auth-token: ${CODEMAGIC_API_TOKEN}" -o "${ARTIFACTS_DIR}/${NAME}" "${URL}"
  done

# "warning": the build finished but a non-blocking step (e.g. publishing) reported a problem
if [ "${STATUS}" = "warning" ]; then
  echo "Codemagic build finished with warnings: see the Codemagic logs." >&2
elif [ "${STATUS}" != "finished" ]; then
  echo "Codemagic build ended with status '${STATUS}'." >&2
  exit 1
fi
echo "Codemagic build finished successfully."
