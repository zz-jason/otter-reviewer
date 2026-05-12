#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/install-app-secrets-from-manifest-code.sh owner/repo manifest-code [private-key-output]

Exchanges a GitHub App manifest code for App credentials and installs the
OTTER_REVIEWER_APP_ID and OTTER_REVIEWER_PRIVATE_KEY repository secrets.

The manifest code is the temporary code GitHub adds to the redirect URL after
creating the app from docs/github-app-manifest.json.
USAGE
}

repo="${1:-}"
code="${2:-}"
private_key_output="${3:-${HOME}/.config/otter-reviewer/otter-reviewer.private-key.pem}"

if [[ -z "${repo}" || -z "${code}" || "${repo}" == -* ]]; then
  usage
  exit 2
fi

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 2
  fi
}

need gh
need jq

tmp_json="$(mktemp)"
trap 'rm -f "${tmp_json}"' EXIT

gh api \
  --method POST \
  "/app-manifests/${code}/conversions" > "${tmp_json}"

app_id="$(jq -r '.id' "${tmp_json}")"
app_slug="$(jq -r '.slug // empty' "${tmp_json}")"
pem="$(jq -r '.pem' "${tmp_json}")"

if [[ -z "${app_id}" || "${app_id}" == "null" || -z "${pem}" || "${pem}" == "null" ]]; then
  echo "Manifest conversion did not return an app id and private key" >&2
  exit 2
fi

mkdir -p "$(dirname "${private_key_output}")"
umask 077
printf '%s\n' "${pem}" > "${private_key_output}"

gh secret set OTTER_REVIEWER_APP_ID --repo "${repo}" --body "${app_id}" >/dev/null
gh secret set OTTER_REVIEWER_PRIVATE_KEY --repo "${repo}" < "${private_key_output}" >/dev/null

echo "Installed Otter Reviewer app secrets in ${repo}"
echo "App ID: ${app_id}"
if [[ -n "${app_slug}" ]]; then
  echo "App slug: ${app_slug}"
fi
echo "Private key saved at ${private_key_output}"
