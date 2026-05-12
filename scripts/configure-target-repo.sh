#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/configure-target-repo.sh owner/repo [options]

Options:
  --action-ref REF        otter-reviewer-action ref to use, default: v1
  --runs-on JSON          runs-on JSON array, default: ["self-hosted","otter-reviewer"]
  --branch BRANCH         target branch, default: repository default branch
  --no-secrets            do not set GitHub App secrets

Optional secret environment:
  OTTER_REVIEWER_APP_ID
  OTTER_REVIEWER_PRIVATE_KEY
  OTTER_REVIEWER_PRIVATE_KEY_FILE
  OTTER_REVIEWER_INSTALLATION_ID
USAGE
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
esac

repo="${1:-}"
if [[ -z "${repo}" || "${repo}" == -* ]]; then
  usage
  exit 2
fi
shift

action_ref="v1"
runs_on='["self-hosted","otter-reviewer"]'
branch=""
set_secrets="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action-ref)
      action_ref="${2:?missing value for --action-ref}"
      shift 2
      ;;
    --reviewer-ref)
      action_ref="${2:?missing value for --reviewer-ref}"
      shift 2
      ;;
    --runs-on)
      runs_on="${2:?missing value for --runs-on}"
      shift 2
      ;;
    --branch)
      branch="${2:?missing value for --branch}"
      shift 2
      ;;
    --no-secrets)
      set_secrets="false"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 2
  fi
}

need gh
need sed
need base64

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_template="${script_dir}/../templates/otter-review.yml"
workflow_path=".github/workflows/otter-review.yml"
tmp_workflow="$(mktemp)"
trap 'rm -f "${tmp_workflow}"' EXIT

sed \
  -e "s|zz-jason/otter-reviewer-action@v1|zz-jason/otter-reviewer-action@${action_ref}|g" \
  -e "s|fromJSON('\\[\"self-hosted\",\"otter-reviewer\"\\]')|fromJSON('${runs_on}')|g" \
  "${source_template}" > "${tmp_workflow}"

if [[ -z "${branch}" ]]; then
  branch="$(gh repo view "${repo}" --json defaultBranchRef --jq '.defaultBranchRef.name')"
fi

content="$(base64 "${tmp_workflow}" | tr -d '\n')"
sha="$(gh api "/repos/${repo}/contents/${workflow_path}?ref=${branch}" --jq '.sha' 2>/dev/null || true)"

api_args=(
  --method PUT
  "/repos/${repo}/contents/${workflow_path}"
  -f "message=Install Otter Reviewer workflow"
  -f "content=${content}"
  -f "branch=${branch}"
)

if [[ -n "${sha}" ]]; then
  api_args+=(-f "sha=${sha}")
fi

gh api "${api_args[@]}" >/dev/null
echo "Installed ${workflow_path} in ${repo}@${branch}"

if [[ "${set_secrets}" != "true" ]]; then
  exit 0
fi

if [[ -n "${OTTER_REVIEWER_APP_ID:-}" ]]; then
  gh secret set OTTER_REVIEWER_APP_ID --repo "${repo}" --body "${OTTER_REVIEWER_APP_ID}" >/dev/null
  echo "Set secret OTTER_REVIEWER_APP_ID"
fi

if [[ -n "${OTTER_REVIEWER_PRIVATE_KEY_FILE:-}" ]]; then
  gh secret set OTTER_REVIEWER_PRIVATE_KEY --repo "${repo}" < "${OTTER_REVIEWER_PRIVATE_KEY_FILE}" >/dev/null
  echo "Set secret OTTER_REVIEWER_PRIVATE_KEY from file"
elif [[ -n "${OTTER_REVIEWER_PRIVATE_KEY:-}" ]]; then
  printf '%s' "${OTTER_REVIEWER_PRIVATE_KEY}" | gh secret set OTTER_REVIEWER_PRIVATE_KEY --repo "${repo}" >/dev/null
  echo "Set secret OTTER_REVIEWER_PRIVATE_KEY"
fi

if [[ -n "${OTTER_REVIEWER_INSTALLATION_ID:-}" ]]; then
  gh secret set OTTER_REVIEWER_INSTALLATION_ID --repo "${repo}" --body "${OTTER_REVIEWER_INSTALLATION_ID}" >/dev/null
  echo "Set secret OTTER_REVIEWER_INSTALLATION_ID"
fi
