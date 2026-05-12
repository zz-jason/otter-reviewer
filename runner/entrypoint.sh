#!/usr/bin/env bash
set -euo pipefail

RUNNER_HOME="${RUNNER_HOME:-/home/runner/actions-runner}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-/home/runner/_work}"
RUNNER_URL="${RUNNER_URL:-https://github.com/${GITHUB_REPOSITORY:-}}"
RUNNER_NAME="${RUNNER_NAME:-otter-reviewer-$(hostname)}"
RUNNER_LABELS="${RUNNER_LABELS:-otter-reviewer,docker}"
RUNNER_EPHEMERAL="${RUNNER_EPHEMERAL:-false}"
CODEX_HOME="${CODEX_HOME:-/home/runner/.codex}"

if [[ -z "${GITHUB_REPOSITORY:-}" && -z "${RUNNER_URL:-}" ]]; then
  echo "GITHUB_REPOSITORY or RUNNER_URL is required" >&2
  exit 2
fi

if [[ ! -f "${CODEX_HOME}/config.toml" ]]; then
  echo "Codex config not found at ${CODEX_HOME}/config.toml" >&2
  echo "Mount the host ~/.codex/config.toml into the container." >&2
  exit 2
fi

if [[ ! -d "${RUNNER_HOME}" || ! -x "${RUNNER_HOME}/config.sh" ]]; then
  mkdir -p "${RUNNER_HOME}"
  cd "${RUNNER_HOME}"

  case "$(uname -m)" in
    x86_64) runner_arch="x64" ;;
    aarch64 | arm64) runner_arch="arm64" ;;
    *) echo "Unsupported runner architecture: $(uname -m)" >&2; exit 2 ;;
  esac

  release_json="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest)"
  asset_url="$(jq -r --arg arch "${runner_arch}" '.assets[] | select(.name | test("linux-" + $arch + "-.*\\.tar\\.gz$")) | .browser_download_url' <<<"${release_json}" | head -n 1)"
  if [[ -z "${asset_url}" || "${asset_url}" == "null" ]]; then
    echo "Could not resolve latest actions runner asset for linux-${runner_arch}" >&2
    exit 2
  fi

  curl -fsSL "${asset_url}" -o actions-runner.tar.gz
  tar -xzf actions-runner.tar.gz
  rm -f actions-runner.tar.gz
else
  cd "${RUNNER_HOME}"
fi

get_runner_token() {
  if [[ -n "${RUNNER_TOKEN:-}" ]]; then
    printf '%s\n' "${RUNNER_TOKEN}"
    return 0
  fi

  if [[ -n "${GITHUB_PAT:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
    curl -fsSL \
      -X POST \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GITHUB_PAT}" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/runners/registration-token" \
      | jq -r '.token'
    return 0
  fi

  echo "RUNNER_TOKEN or GITHUB_PAT is required to register the runner" >&2
  return 2
}

get_remove_token() {
  if [[ -n "${GITHUB_PAT:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
    curl -fsSL \
      -X POST \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GITHUB_PAT}" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/runners/remove-token" \
      | jq -r '.token'
    return 0
  fi

  printf '%s\n' "${RUNNER_TOKEN:-}"
}

cleanup() {
  if [[ -f "${RUNNER_HOME}/.runner" ]]; then
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

exec ./run.sh
