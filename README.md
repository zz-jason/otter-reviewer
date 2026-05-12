# Otter Reviewer

Otter Reviewer is a self-hosted GitHub Actions PR reviewer. It runs a configurable agent CLI on your runner, converts the agent output into inline pull request review comments, and posts those comments through a GitHub App identity.

The publishable Marketplace action lives in `zz-jason/otter-reviewer-action`. This repository keeps the product docs, GitHub App setup helpers, target-repository templates, reusable workflow wrapper, and runner scripts.

Codex is the end-to-end validated default agent. Other review-capable CLIs can be used by configuring `agent-command`, `agent-args-json`, and `agent-env-pass`.

## Architecture

- Target repositories run a thin workflow on a self-hosted runner labeled `otter-reviewer`.
- The workflow checks out the PR head and invokes `zz-jason/otter-reviewer-action@v1`.
- The action resolves the PR diff, calls the configured review agent CLI, validates JSON output, filters comments to valid RIGHT-side diff lines, and posts a pull request review.
- GitHub App credentials are supplied as secrets so the visible GitHub author is the App, not `github-actions[bot]`.

## Review Flow

```mermaid
sequenceDiagram
    autonumber
    participant Dev as Developer
    participant RepoPR as Target Repository / Pull Request
    participant Actions as GitHub Actions
    participant Runner as Self-hosted Runner
    participant Action as otter-reviewer-action
    participant App as GitHub App API
    participant Agent as Configured Agent CLI

    Dev->>RepoPR: Open, update, or manually dispatch review
    RepoPR->>Actions: Run .github/workflows/otter-review.yml
    Actions->>Runner: Schedule job with self-hosted + otter-reviewer labels
    Runner->>RepoPR: Checkout PR head
    Runner->>Action: Run zz-jason/otter-reviewer-action@v1
    Action->>RepoPR: Fetch PR metadata with read-only GITHUB_TOKEN
    Action->>Action: Refuse fork PR unless allow-fork-prs is enabled
    Action->>RepoPR: Compute base...head diff
    Action->>Agent: Run configured review agent with prompt, diff, and schema
    Note over Agent: Codex is the validated default; other agent CLIs are configurable
    Agent-->>Action: JSON summary and candidate inline comments
    Action->>Action: Validate schema and filter to RIGHT-side diff lines
    Action->>App: Sign GitHub App JWT with OTTER_REVIEWER_PRIVATE_KEY
    Action->>App: Exchange JWT for installation access token
    App-->>Action: Token scoped to the target repository
    Action->>RepoPR: POST pull request review with inline comments
    RepoPR-->>Dev: Show comments authored by Otter Reviewer app
```

## Target Repository Setup

1. Create a GitHub App named `Otter Reviewer`.
2. Install it on the target repository.
3. Add repository or narrowly scoped organization secrets:
   - `OTTER_REVIEWER_APP_ID`
   - `OTTER_REVIEWER_PRIVATE_KEY`
   - `OTTER_REVIEWER_INSTALLATION_ID`, optional
4. Copy `templates/otter-review.yml` to `.github/workflows/otter-review.yml` in the target repository.
5. Start a self-hosted runner with the `otter-reviewer` label and the agent CLI you want to use.

See `docs/github-app.md` and `docs/github-app-manifest.json` for app creation details, and `docs/configure-target-repo.md` for the full repository setup.

For a remote repository, install the workflow and secrets with:

```bash
export OTTER_REVIEWER_APP_ID="123456"
export OTTER_REVIEWER_PRIVATE_KEY_FILE="$HOME/.config/otter-reviewer/otter-reviewer.private-key.pem"

./scripts/configure-target-repo.sh owner/repo
```

Secrets can also live at the organization level when the organization secret is granted only to the intended repositories; then use `--no-secrets` and only install the workflow in each repository.

## Published Action

Target repositories can call the Marketplace action directly:

```yaml
jobs:
  review:
    if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository
    runs-on: [self-hosted, otter-reviewer]
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
          persist-credentials: false
          ref: ${{ github.event.pull_request.head.sha || github.sha }}

      - uses: zz-jason/otter-reviewer-action@v1
        with:
          app-id: ${{ secrets.OTTER_REVIEWER_APP_ID }}
          private-key: ${{ secrets.OTTER_REVIEWER_PRIVATE_KEY }}
          installation-id: ${{ secrets.OTTER_REVIEWER_INSTALLATION_ID }}
          max-inline-comments: "10"
          post-empty-review: "true"
          pr-number: ${{ github.event.pull_request.number || github.event.inputs.pr_number }}
```

For stricter supply-chain pinning, use a full release tag or commit SHA instead of `@v1`.

## Custom Agent CLI

The default adapter runs `codex exec` with the runner's `${CODEX_HOME:-$HOME/.codex}/config.toml`. A repository can use another agent CLI by passing an executable, JSON arguments, and any required credential environment variables:

```yaml
- uses: zz-jason/otter-reviewer-action@v1
  with:
    app-id: ${{ secrets.OTTER_REVIEWER_APP_ID }}
    private-key: ${{ secrets.OTTER_REVIEWER_PRIVATE_KEY }}
    pr-number: ${{ github.event.pull_request.number }}
    agent-command: my-review-agent
    agent-args-json: '["review", "--schema", "{schemaPath}", "--output", "{outputPath}"]'
    agent-env-pass: MY_AGENT_API_KEY
  env:
    MY_AGENT_API_KEY: ${{ secrets.MY_AGENT_API_KEY }}
```

Custom agents receive the review prompt on stdin and must output JSON matching the `zz-jason/otter-reviewer-action` schema, either on stdout or at `OTTER_AGENT_OUTPUT_PATH`.

## Security Defaults

- Fork PRs are skipped by default in the template and refused by the action runtime, including manual dispatch.
- Runner scripts default to ephemeral registration and remove runner registration credentials before starting the runner listener.
- Checkout examples use `persist-credentials: false` so agent processes cannot read the workflow token from local git config.
- GitHub App private key handling is split from agent execution: the action prepares the review first, then signs and posts after the agent has exited.
- Organization-level App secrets should be scoped to selected repositories or split by trust domain.

## Reusable Workflow Wrapper

This repository also exposes `.github/workflows/review.yml` as a wrapper around `zz-jason/otter-reviewer-action@v1`. It is useful when you want centralized defaults, but direct action usage is the recommended path for Marketplace consumers.

## Runner

Host runner:

```bash
export GITHUB_REPOSITORY=owner/repo
export GITHUB_PAT="$(gh auth token)"
export CODEX_HOME="$HOME/.codex"
export RUNNER_CACHE_DIR="$HOME/.cache/otter-reviewer/actions-runner"
export RUNNER_EPHEMERAL=true

./runner/start-host-runner.sh
```

Docker runner:

```bash
export GITHUB_REPOSITORY=owner/repo
export GITHUB_PAT="$(gh auth token)"
export CODEX_CONFIG="$HOME/.codex/config.toml"
export CODEX_VERSION="$(codex --version | awk '{print $2}')"
export RUNNER_CACHE_DIR="$HOME/.cache/otter-reviewer/actions-runner"
export RUNNER_EPHEMERAL=true

docker compose -f runner/docker-compose.yml up --build
```

## Local Checks

```bash
npm test
npm run check
bash -n runner/entrypoint.sh runner/start-host-runner.sh scripts/install-target-workflow.sh scripts/configure-target-repo.sh
scripts/install-app-secrets-from-manifest-code.sh --help
GITHUB_REPOSITORY=owner/repo GITHUB_PAT=dummy docker compose -f runner/docker-compose.yml config
```
