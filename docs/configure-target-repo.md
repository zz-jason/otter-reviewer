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

Add these secrets to every target repo, or define them as organization secrets granted only to the selected target repositories:

- `OTTER_REVIEWER_APP_ID`: numeric GitHub App ID
- `OTTER_REVIEWER_PRIVATE_KEY`: private key PEM for the app
- `OTTER_REVIEWER_INSTALLATION_ID`: optional; omit it unless you want to avoid installation lookup

The private key can be stored as multi-line PEM text. Escaped `\n` text and base64-encoded PEM also work.

## 3. Add the workflow

Copy `templates/otter-review.yml` into the target repo at `.github/workflows/otter-review.yml`, or run:

```bash
./scripts/install-target-workflow.sh /path/to/target/repo v1 '["self-hosted","otter-reviewer"]'
```

For a repository that is not cloned locally, run:

```bash
export OTTER_REVIEWER_APP_ID="123456"
export OTTER_REVIEWER_PRIVATE_KEY_FILE="$HOME/Downloads/otter-reviewer.private-key.pem"

./scripts/configure-target-repo.sh owner/repo
```

The remote script commits `.github/workflows/otter-review.yml` to the repository default branch and sets any GitHub App secrets provided through the environment. It installs a workflow that calls `zz-jason/otter-reviewer-action@v1` by default. If app secrets are already configured as organization secrets, use:

```bash
./scripts/configure-target-repo.sh owner/repo --no-secrets
```

Use `--action-ref v1.0.3` or a commit SHA when a repository needs stricter action pinning.

## 4. Start a runner

The runner must have:

- `git`, `node`, and `jq`
- `codex` on `PATH` and `~/.codex/config.toml` available through `CODEX_HOME` when using the default Codex adapter
- any custom agent CLI and credentials required by that repository when using `agent-command`
- labels matching the target workflow, by default `self-hosted` and `otter-reviewer`

Host runner:

```bash
export GITHUB_REPOSITORY=owner/repo
export RUNNER_GITHUB_APP_ID=123456
export RUNNER_GITHUB_APP_INSTALLATION_ID=987654
export RUNNER_GITHUB_APP_PRIVATE_KEY_FILE=/etc/otter-reviewer/runner-registrar.private-key.pem
export CODEX_HOME="$HOME/.codex"
export RUNNER_CACHE_DIR="$HOME/.cache/otter-reviewer/actions-runner"
export RUNNER_EPHEMERAL=true

./runner/start-host-runner.sh
```

Use a separate runner registrar GitHub App for this credential path. For repo-scoped runners, grant repository `Administration: read and write` only to selected repositories. For org-scoped runners, set `RUNNER_SCOPE=org` and `GITHUB_ORG=owner`, and grant organization `Self-hosted runners: read and write`.

Docker runner:

```bash
export GITHUB_REPOSITORY=owner/repo
export RUNNER_GITHUB_APP_ID=123456
export RUNNER_GITHUB_APP_INSTALLATION_ID=987654
export RUNNER_GITHUB_APP_PRIVATE_KEY="$(cat /etc/otter-reviewer/runner-registrar.private-key.pem)"
export CODEX_CONFIG="$HOME/.codex/config.toml"
export CODEX_VERSION="$(codex --version | awk '{print $2}')"
export RUNNER_CACHE_DIR="$HOME/.cache/otter-reviewer/actions-runner"
export RUNNER_EPHEMERAL=true

docker compose -f runner/docker-compose.yml up --build
```

## 5. Optional repo-specific review instructions

Create `.otter-reviewer.md` in a target repository to add project-specific review guidance. The contents are appended to the agent prompt for that repository only.

## 6. Optional custom agent CLI

Codex is the default adapter. To use another agent, edit the `Run Otter Reviewer` step in `.github/workflows/otter-review.yml`:

```yaml
      - name: Run Otter Reviewer
        uses: zz-jason/otter-reviewer-action@v1
        with:
          app-id: ${{ secrets.OTTER_REVIEWER_APP_ID }}
          private-key: ${{ secrets.OTTER_REVIEWER_PRIVATE_KEY }}
          pr-number: ${{ github.event.pull_request.number || github.event.inputs.pr_number }}
          agent-command: my-review-agent
          agent-args-json: '["review", "--schema", "{schemaPath}", "--output", "{outputPath}"]'
          agent-env-pass: MY_AGENT_API_KEY
        env:
          MY_AGENT_API_KEY: ${{ secrets.MY_AGENT_API_KEY }}
```

The custom agent receives the prompt on stdin and must return JSON matching the action schema.

## Multi-repository rollout pattern

For many repositories in the same trust domain, keep the same GitHub App installed at the organization/account level, expose `OTTER_REVIEWER_APP_ID` and `OTTER_REVIEWER_PRIVATE_KEY` as selected-repository organization secrets, and run:

```bash
for repo in owner/repo-a owner/repo-b owner/repo-c; do
  ./scripts/configure-target-repo.sh "$repo" --no-secrets
done
```

Only override `--runs-on` when a repository needs a different runner pool, for example `["self-hosted","otter-reviewer","large"]`.

Use separate GitHub Apps or separate private keys for repositories with different trust boundaries.
