# Configure a Target Repository

This is the minimal setup for any repository that should receive Otter Reviewer PR reviews.

## 1. Install the GitHub App

Create or use a GitHub App named `Otter Reviewer` and install it on the target repository.

Required repository permissions:

- `Contents`: read
- `Pull requests`: read and write
- `Metadata`: read, granted automatically

No webhook is required for the workflow-driven setup.

## 2. Add repository or organization secrets

Add these secrets to every target repo, or define them once as organization secrets and grant repo access:

- `OTTER_REVIEWER_APP_ID`: numeric GitHub App ID
- `OTTER_REVIEWER_PRIVATE_KEY`: private key PEM for the app
- `OTTER_REVIEWER_INSTALLATION_ID`: optional; omit it unless you want to avoid installation lookup

The private key can be stored as multi-line PEM text. Escaped `\n` text and base64-encoded PEM also work.

## 3. Add the workflow

Copy `templates/otter-review.yml` into the target repo at `.github/workflows/otter-review.yml`, or run:

```bash
./scripts/install-target-workflow.sh /path/to/target/repo main '["self-hosted","otter-reviewer"]'
```

For a repository that is not cloned locally, run:

```bash
export OTTER_REVIEWER_APP_ID="123456"
export OTTER_REVIEWER_PRIVATE_KEY_FILE="$HOME/Downloads/otter-reviewer.private-key.pem"

./scripts/configure-target-repo.sh owner/repo
```

The remote script commits `.github/workflows/otter-review.yml` to the repository default branch and sets any GitHub App secrets provided through the environment. If app secrets are already configured as organization secrets, use:

```bash
./scripts/configure-target-repo.sh owner/repo --no-secrets
```

For private `otter-reviewer` repositories, make sure GitHub Actions in target repositories can access this repository as a reusable workflow/action. If that is not available in your GitHub plan or account layout, copy `bin/`, `schema/`, and `action.yml` into the target repo and change the workflow step to `uses: ./`.

## 4. Start a runner

The runner must have:

- `codex` on `PATH`
- `git`, `node`, and `jq`
- `~/.codex/config.toml` available through `CODEX_HOME`
- labels matching the target workflow, by default `self-hosted` and `otter-reviewer`

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

## 5. Optional repo-specific review instructions

Create `.otter-reviewer.md` in a target repository to add project-specific review guidance. The contents are appended to the Codex prompt for that repository only.

## Multi-repository rollout pattern

For many repositories, keep the same GitHub App installed at the organization/account level, expose `OTTER_REVIEWER_APP_ID` and `OTTER_REVIEWER_PRIVATE_KEY` as organization secrets, and run:

```bash
for repo in owner/repo-a owner/repo-b owner/repo-c; do
  ./scripts/configure-target-repo.sh "$repo" --no-secrets
done
```

Only override `--runs-on` when a repository needs a different runner pool, for example `["self-hosted","otter-reviewer","large"]`.
