#!/usr/bin/env bash

otter_runner_scope_path() {
  case "${RUNNER_SCOPE:-repo}" in
    repo)
      if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
        echo "GITHUB_REPOSITORY is required for repo-scoped runner registration" >&2
        return 2
      fi
      printf 'repos/%s/actions/runners' "${GITHUB_REPOSITORY}"
      ;;
    org)
      if [[ -z "${GITHUB_ORG:-}" ]]; then
        echo "GITHUB_ORG is required for org-scoped runner registration" >&2
        return 2
      fi
      printf 'orgs/%s/actions/runners' "${GITHUB_ORG}"
      ;;
    *)
      echo "Unsupported RUNNER_SCOPE=${RUNNER_SCOPE}. Use repo or org." >&2
      return 2
      ;;
  esac
}

otter_has_runner_github_app() {
  [[ -n "${RUNNER_GITHUB_APP_ID:-}" ]] \
    && [[ -n "${RUNNER_GITHUB_APP_INSTALLATION_ID:-}" ]] \
    && { [[ -n "${RUNNER_GITHUB_APP_PRIVATE_KEY:-}" ]] || [[ -n "${RUNNER_GITHUB_APP_PRIVATE_KEY_FILE:-}" ]]; }
}

otter_runner_github_app_jwt() {
  node <<'NODE'
const fs = require("fs");
const crypto = require("crypto");

const appId = process.env.RUNNER_GITHUB_APP_ID;
let privateKey = process.env.RUNNER_GITHUB_APP_PRIVATE_KEY || "";
if (!privateKey && process.env.RUNNER_GITHUB_APP_PRIVATE_KEY_FILE) {
  privateKey = fs.readFileSync(process.env.RUNNER_GITHUB_APP_PRIVATE_KEY_FILE, "utf8");
}
if (!appId || !privateKey) {
  throw new Error("RUNNER_GITHUB_APP_ID and runner GitHub App private key are required");
}

const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
const now = Math.floor(Date.now() / 1000);
const header = encode({ alg: "RS256", typ: "JWT" });
const payload = encode({ iat: now - 60, exp: now + 540, iss: appId });
const signature = crypto.sign("RSA-SHA256", Buffer.from(`${header}.${payload}`), privateKey).toString("base64url");
process.stdout.write(`${header}.${payload}.${signature}`);
NODE
}

otter_runner_installation_token() {
  local jwt api_url
  api_url="${GITHUB_API_URL:-https://api.github.com}"
  jwt="$(otter_runner_github_app_jwt)"
  curl -fsSL \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${jwt}" \
    "${api_url}/app/installations/${RUNNER_GITHUB_APP_INSTALLATION_ID}/access_tokens" \
    | jq -r '.token'
}

otter_runner_token() {
  local kind path token api_url
  kind="${1:?token kind is required}"
  api_url="${GITHUB_API_URL:-https://api.github.com}"

  if otter_has_runner_github_app; then
    token="$(otter_runner_installation_token)"
    path="$(otter_runner_scope_path)"
    curl -fsSL \
      -X POST \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${token}" \
      "${api_url}/${path}/${kind}-token" \
      | jq -r '.token'
    return 0
  fi

  if [[ "${kind}" == "registration" && -n "${RUNNER_TOKEN:-}" ]]; then
    printf '%s\n' "${RUNNER_TOKEN}"
    return 0
  fi

  if [[ -n "${GITHUB_PAT:-}" ]]; then
    path="$(otter_runner_scope_path)"
    curl -fsSL \
      -X POST \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GITHUB_PAT}" \
      "${api_url}/${path}/${kind}-token" \
      | jq -r '.token'
    return 0
  fi

  if [[ "${kind}" == "remove" && -n "${RUNNER_TOKEN:-}" ]]; then
    printf '%s\n' "${RUNNER_TOKEN}"
    return 0
  fi

  echo "Runner registration needs RUNNER_GITHUB_APP_* credentials, RUNNER_TOKEN, or GITHUB_PAT" >&2
  return 2
}
