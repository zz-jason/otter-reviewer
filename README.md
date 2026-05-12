# Otter Reviewer

Otter Reviewer is a self-hosted GitHub Actions PR reviewer that runs Codex and posts inline review comments through a GitHub App identity.

The important identity detail is intentional: comments are posted with a GitHub App installation token, not `GITHUB_TOKEN`. If the GitHub App is named `Otter Reviewer`, GitHub shows the review as coming from Otter Reviewer instead of `github-actions[bot]`.

## Architecture

- Target repositories run a thin workflow on a self-hosted runner labeled `otter-reviewer`.
- The workflow checks out the PR head and invokes this repository's reusable workflow or composite action.
- `bin/otter-reviewer.js` resolves the PR diff, calls `codex exec` with the runner's `CODEX_HOME/config.toml`, validates Codex JSON output, filters comments to valid RIGHT-side diff lines, and posts a pull request review.
- GitHub App credentials are supplied as secrets so the visible GitHub author is the App, not the workflow bot.

## Target Repository Setup

1. Create a GitHub App named `Otter Reviewer`.
2. Install it on the target repository.
3. Add these secrets to the target repository or organization:
   - `OTTER_REVIEWER_APP_ID`
   - `OTTER_REVIEWER_PRIVATE_KEY`
   - `OTTER_REVIEWER_INSTALLATION_ID`, optional
4. Copy `templates/otter-review.yml` to `.github/workflows/otter-review.yml` in the target repository.
5. Start a self-hosted runner with the `otter-reviewer` label.

See `docs/github-app.md` and `docs/github-app-manifest.json` for app creation details, and `docs/configure-target-repo.md` for the full repository setup.

For a remote repository, the workflow install can be one command:

```bash
export OTTER_REVIEWER_APP_ID="123456"
export OTTER_REVIEWER_PRIVATE_KEY_FILE="$HOME/Downloads/otter-reviewer.private-key.pem"

./scripts/configure-target-repo.sh owner/repo
```

Secrets can also live at the organization level; then use `--no-secrets` and only install the workflow in each repository.

## Reusable Workflow

Target repositories can use:

```yaml
jobs:
  review:
    uses: zz-jason/otter-reviewer/.github/workflows/review.yml@main
    with:
      runs-on: '["self-hosted","otter-reviewer"]'
      max-inline-comments: "10"
      pr_number: ${{ github.event.pull_request.number || github.event.inputs.pr_number }}
    secrets:
      OTTER_REVIEWER_APP_ID: ${{ secrets.OTTER_REVIEWER_APP_ID }}
      OTTER_REVIEWER_PRIVATE_KEY: ${{ secrets.OTTER_REVIEWER_PRIVATE_KEY }}
      OTTER_REVIEWER_INSTALLATION_ID: ${{ secrets.OTTER_REVIEWER_INSTALLATION_ID }}
```

## Runner

Host runner:

```bash
export GITHUB_REPOSITORY=owner/repo
export GITHUB_PAT="$(gh auth token)"
export CODEX_HOME="$HOME/.codex"
export RUNNER_EPHEMERAL=true

./runner/start-host-runner.sh
```

Docker runner:

```bash
export GITHUB_REPOSITORY=owner/repo
export GITHUB_PAT="$(gh auth token)"
export CODEX_CONFIG="$HOME/.codex/config.toml"
export CODEX_VERSION="$(codex --version | awk '{print $2}')"
export RUNNER_EPHEMERAL=true

docker compose -f runner/docker-compose.yml up --build
```

## Local Checks

```bash
npm test
npm run check
bash -n runner/entrypoint.sh runner/start-host-runner.sh scripts/install-target-workflow.sh scripts/configure-target-repo.sh
docker compose -f runner/docker-compose.yml config
```
