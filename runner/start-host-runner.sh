#!/usr/bin/env bash
set -euo pipefail

RUNNER_SCOPE="${RUNNER_SCOPE:-repo}"
case "${RUNNER_SCOPE}" in
  repo)
    GITHUB_REPOSITORY="${GITHUB_REPOSITORY:?set target repository, for example zz-jason/otter-review-test}"
    RUNNER_URL="${RUNNER_URL:-https://github.com/${GITHUB_REPOSITORY}}"
    default_runner_root="${HOME}/actions-runner-${GITHUB_REPOSITORY//\//-}-otter"
    ;;
  org)
    GITHUB_ORG="${GITHUB_ORG:?set target organization, for example archebase}"
    RUNNER_URL="${RUNNER_URL:-https://github.com/${GITHUB_ORG}}"
    default_runner_root="${HOME}/actions-runner-${GITHUB_ORG}-otter"
    ;;
  *)
    echo "Unsupported RUNNER_SCOPE=${RUNNER_SCOPE}. Use repo or org." >&2
    exit 2
    ;;
esac
RUNNER_NAME="${RUNNER_NAME:-otter-reviewer-host-$(hostname)}"
RUNNER_LABELS="${RUNNER_LABELS:-otter-reviewer,host}"
RUNNER_EPHEMERAL="${RUNNER_EPHEMERAL:-true}"
RUNNER_ROOT="${RUNNER_ROOT:-${default_runner_root}}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-${RUNNER_ROOT}/_work}"
RUNNER_CACHE_DIR="${RUNNER_CACHE_DIR:-${HOME}/.cache/otter-reviewer/actions-runner}"
CODEX_HOME="${CODEX_HOME:-${HOME}/.codex}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=runner/lib/runner-token.sh
source "${script_dir}/lib/runner-token.sh"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 2
  fi
}

need curl
need git
need jq

if [[ "${REQUIRE_CODEX:-true}" == "true" ]]; then
  need codex

  if [[ ! -f "${CODEX_HOME}/config.toml" ]]; then
    echo "Codex config not found at ${CODEX_HOME}/config.toml" >&2
    exit 2
  fi
fi

mkdir -p "${RUNNER_ROOT}" "${RUNNER_WORKDIR}"
if [[ "${RUNNER_EPHEMERAL}" == "true" ]]; then
  find "${RUNNER_WORKDIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi
cd "${RUNNER_ROOT}"

if [[ ! -x ./config.sh ]]; then
  case "$(uname -m)" in
    x86_64) runner_arch="x64" ;;
    aarch64 | arm64) runner_arch="arm64" ;;
    *) echo "Unsupported runner architecture: $(uname -m)" >&2; exit 2 ;;
  esac

  release_json="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest)"
  asset_url="$(jq -r --arg arch "${runner_arch}" '.assets[] | select(.name | test("linux-" + $arch + "-.*\\.tar\\.gz$")) | .browser_download_url' <<<"${release_json}" | head -n 1)"
  asset_name="$(basename "${asset_url}")"
  if [[ -z "${asset_url}" || "${asset_url}" == "null" ]]; then
    echo "Could not resolve latest actions runner asset for linux-${runner_arch}" >&2
    exit 2
  fi

  mkdir -p "${RUNNER_CACHE_DIR}"
  cached_asset="${RUNNER_CACHE_DIR}/${asset_name}"
  if [[ ! -s "${cached_asset}" ]]; then
    tmp_asset="${cached_asset}.tmp.$$"
    curl -fsSL "${asset_url}" -o "${tmp_asset}"
    mv "${tmp_asset}" "${cached_asset}"
  fi

  cp "${cached_asset}" actions-runner.tar.gz
  tar -xzf actions-runner.tar.gz
  rm -f actions-runner.tar.gz
fi

get_runner_token() {
  otter_runner_token registration
}

get_remove_token() {
  otter_runner_token remove
}

cleanup() {
  if [[ -f "${RUNNER_ROOT}/.runner" ]]; then
    remove_token="$(get_remove_token || true)"
    if [[ -n "${remove_token}" && "${remove_token}" != "null" ]]; then
      ./config.sh remove --unattended --token "${remove_token}" || true
    fi
  fi
}
trap cleanup EXIT INT TERM

token="$(get_runner_token)"
if [[ -z "${token}" || "${token}" == "null" ]]; then
  echo "Could not obtain a runner registration token" >&2
  exit 2
fi

config_args=(
  --url "${RUNNER_URL}"
  --token "${token}"
  --name "${RUNNER_NAME}"
  --labels "${RUNNER_LABELS}"
  --work "${RUNNER_WORKDIR}"
  --unattended
  --replace
)

if [[ "${RUNNER_EPHEMERAL}" == "true" ]]; then
  config_args+=(--ephemeral)
fi

./config.sh "${config_args[@]}"

CODEX_HOME="${CODEX_HOME}" env \
  -u GITHUB_PAT \
  -u RUNNER_TOKEN \
  -u RUNNER_GITHUB_APP_ID \
  -u RUNNER_GITHUB_APP_INSTALLATION_ID \
  -u RUNNER_GITHUB_APP_PRIVATE_KEY \
  -u RUNNER_GITHUB_APP_PRIVATE_KEY_FILE \
  ./run.sh
