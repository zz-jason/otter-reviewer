#!/usr/bin/env bash
set -euo pipefail

target_repo="${1:-}"
reviewer_ref="${2:-main}"
runs_on="${3:-[\"self-hosted\",\"otter-reviewer\"]}"

if [[ -z "${target_repo}" ]]; then
  echo "Usage: $0 /path/to/target-repo [reviewer-ref] [runs-on-json]" >&2
  exit 2
fi

if [[ ! -d "${target_repo}/.git" ]]; then
  echo "Target path is not a git repository: ${target_repo}" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_template="${script_dir}/../templates/otter-review.yml"
target_workflow="${target_repo}/.github/workflows/otter-review.yml"

mkdir -p "$(dirname "${target_workflow}")"
sed \
  -e "s|zz-jason/otter-reviewer/.github/workflows/review.yml@main|zz-jason/otter-reviewer/.github/workflows/review.yml@${reviewer_ref}|g" \
  -e "s|runs-on: '\\[\"self-hosted\",\"otter-reviewer\"\\]'|runs-on: '${runs_on}'|g" \
  "${source_template}" > "${target_workflow}"

echo "Installed ${target_workflow}"
