# Shared by the forge scripts (sourced, not run). Moves to the Flutter project root,
# loads the fastlane .env files and sets APP_BUILD_NAME / APP_BUILD_NUMBER, as
# fastlane and its version_metadata lane do, so that the scripts run without Ruby.
#
# Settings (environment):
#   FORGE_FASTLANE_ENV         also loads fastlane/.env.<name>, like fastlane --env <name>
#   FORGE_VERSION_TAG_REGEX    regex whose first group is the version in the tag
#                              (default: ^v?(\d+\.\d+\.\d+))
#   FORGE_BUILD_NUMBER_PREFIX  prefix of the build number (e.g. 100)

FORGE_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_PROJECT_ROOT="$(cd "$FORGE_SCRIPTS_DIR/../../.." && pwd)"
cd "$FORGE_PROJECT_ROOT"

forge_log() {
  echo "[forge] $*" >&2
}

# GitLab CI and Codemagic set CI
forge_is_ci() {
  [[ -n "${CI:-}" ]]
}

# Missing setting: error in CI, where it is a misconfiguration, warning locally.
forge_missing() {
  if forge_is_ci; then
    forge_log "ERROR: $*"
    exit 1
  fi
  forge_log "WARNING: $*"
}

# Boolean setting: "false", "0" and "no" (any case) are false, empty is the default.
forge_bool() {
  local value="${1:-$2}"
  value="$(echo "$value" | tr '[:upper:]' '[:lower:]')"
  [[ "$value" != false && "$value" != 0 && "$value" != no ]]
}

# Exports the KEY=VALUE lines of a dotenv file. Unless override is true, variables
# already set in the environment win.
forge_load_env_file() {
  local file="$1" override="$2" line name
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)= ]] || continue
    name="${BASH_REMATCH[2]}"
    [[ "$override" == true || -z "${!name+x}" ]] || continue
    eval "export $name=${line#*=}"
  done < "$file"
}

# Same order as fastlane: .env and .env.default without overriding the environment,
# then the --env file over it.
forge_load_env_file fastlane/.env false
forge_load_env_file fastlane/.env.default false
if [[ -n "${FORGE_FASTLANE_ENV:-}" ]]; then
  if [[ ! -f "fastlane/.env.$FORGE_FASTLANE_ENV" ]]; then
    forge_log "ERROR: fastlane/.env.$FORGE_FASTLANE_ENV not found"
    exit 1
  fi
  forge_load_env_file "fastlane/.env.$FORGE_FASTLANE_ENV" true
fi

# Unless already set:
#   APP_BUILD_NAME    version captured by FORGE_VERSION_TAG_REGEX in the tag, then
#                     release/x.y.z branch, then pubspec.yaml
#   APP_BUILD_NUMBER  FORGE_BUILD_NUMBER_PREFIX + (PROJECT_BUILD_NUMBER, BUILD_NUMBER,
#                     CI_PIPELINE_IID or 1)
if [[ -z "${APP_BUILD_NAME:-}" ]]; then
  forge_tag="${CM_TAG:-${CI_COMMIT_TAG:-}}"
  forge_branch="${CM_BRANCH:-${CI_COMMIT_BRANCH:-}}"
  forge_build_name=""
  if [[ -n "$forge_tag" ]]; then
    # perl: same regex syntax as the Ruby lanes (\d...)
    forge_build_name="$(FORGE_RE="${FORGE_VERSION_TAG_REGEX:-^v?(\d+\.\d+\.\d+)}" perl -e 'print $1 if $ARGV[0] =~ /$ENV{FORGE_RE}/' "$forge_tag")"
  fi
  if [[ -z "$forge_build_name" && "$forge_branch" =~ ^release/([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    forge_build_name="${BASH_REMATCH[1]}"
  fi
  if [[ -z "$forge_build_name" && -f pubspec.yaml ]]; then
    forge_build_name="$(sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' pubspec.yaml | head -n 1)"
  fi
  if [[ -n "$forge_build_name" ]]; then
    export APP_BUILD_NAME="$forge_build_name"
  fi
fi
if [[ -z "${APP_BUILD_NUMBER:-}" ]]; then
  export APP_BUILD_NUMBER="${FORGE_BUILD_NUMBER_PREFIX:-}${PROJECT_BUILD_NUMBER:-${BUILD_NUMBER:-${CI_PIPELINE_IID:-1}}}"
fi
