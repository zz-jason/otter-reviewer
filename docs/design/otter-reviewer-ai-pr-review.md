# Otter Reviewer AI PR Review

- Co-Authored-By: Codex CLI, GPT-5
- Date: 2026-05-12

## Summary

Otter Reviewer is a reusable AI pull request review system that runs on self-hosted GitHub Actions runners, invokes Codex or another configured review agent CLI, and posts inline review comments through a GitHub App named `Otter Reviewer`. The implementation is split into `otter-reviewer-action`, the publishable Marketplace action runtime, and `otter-reviewer`, the product repository containing runner scripts, setup docs, templates, and an optional reusable workflow wrapper. Target repositories add a small workflow and GitHub App secrets. Posting with a GitHub App installation token is required so GitHub displays the review author as the app identity rather than `github-actions[bot]`.

## Background

The prior experiment proved that a self-hosted runner can execute Codex and post inline review comments on a PR. It also exposed two product requirements for a durable implementation: the visible GitHub reviewer must not be `github-actions[bot]`, and onboarding additional repositories must be cheap. GitHub Actions' default `GITHUB_TOKEN` always attributes API-created reviews to `github-actions[bot]`, so Otter Reviewer must use a different credential class. A GitHub App is the right boundary because it has a named app identity, per-repository installation scope, revocable private-key credentials, and narrowly scoped permissions for pull request review creation. The users are repository owners who want AI review on PRs without copying review logic into every codebase.

## Detailed Design

The system has four components. First, a self-hosted runner runs either on the host or in Docker with labels such as `self-hosted` and `otter-reviewer`; it provides `git`, `node`, and either Codex with the same `~/.codex/config.toml` already used locally or another configured agent CLI. Second, each target repository adds `.github/workflows/otter-review.yml`, which checks out the PR head and calls `zz-jason/otter-reviewer-action@v1`. Third, the action runtime performs prompt construction, schema validation, diff-line filtering, and GitHub API calls. Fourth, the configured agent CLI reviews the prompt and returns structured JSON.

The review flow is:

```text
pull_request event
  -> target repo workflow
  -> self-hosted runner labeled otter-reviewer
  -> checkout PR head
  -> zz-jason/otter-reviewer-action@v1
  -> GitHub App JWT
  -> installation access token for target repo
  -> git diff base...head
  -> configured agent CLI with structured JSON schema
  -> validate/filter comments to valid RIGHT-side diff lines
  -> POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews
```

The GitHub App named `Otter Reviewer` needs `Contents: read`, `Pull requests: read and write`, and the automatic `Metadata: read` permission. The workflow passes `OTTER_REVIEWER_APP_ID` and `OTTER_REVIEWER_PRIVATE_KEY` as secrets. The action first prepares the review without the App private key in the agent step, then signs a short-lived RS256 JWT, resolves the app installation for the current repository unless `OTTER_REVIEWER_INSTALLATION_ID` is set, creates an installation token, and uses that token for review creation. This is the identity mechanism that changes GitHub attribution from `github-actions[bot]` to the app.

Agent output is constrained by the `zz-jason/otter-reviewer-action` JSON schema, which requires a summary plus an array of `{path, line, body, severity}` comments. The action still treats model output as untrusted: it extracts JSON defensively, normalizes comment fields, deduplicates comments, truncates oversized bodies, and drops any comment whose path and line do not map to a RIGHT-side line in the PR diff. This prevents GitHub API failures caused by comments on invalid diff lines.

Target repository configuration stays small. A repo can use the template workflow directly, override runner labels with `runs-on`, set `max-inline-comments`, configure `agent-command` for non-Codex CLIs, and optionally add `.otter-reviewer.md` for local review instructions. `scripts/configure-target-repo.sh owner/repo` installs or updates the workflow through `gh` without requiring a local clone, and it can set app secrets from environment variables. Organization-level secrets can make onboarding additional repositories a workflow-copy operation plus GitHub App installation.

Failure cases are explicit. If no PR number exists, the action exits successfully without posting. If the diff is empty, it skips. If the agent returns no valid comments and `post-empty-review` is false, it skips. If the GitHub App is not installed or lacks permissions, token creation or review posting fails the job. If the runner cannot reach the Codex provider configured in `CODEX_HOME/config.toml` or the configured custom agent fails, the job surfaces that as a runner environment issue.

## Alternative Designs Considered

Using `GITHUB_TOKEN` is simpler but cannot meet the identity requirement because reviews are attributed to `github-actions[bot]`. A bot user's personal access token could show a custom user display name, but it is broader, harder to scope per repository, and weaker operationally than a GitHub App. Keeping the action runtime only in this product repository would make Marketplace publication and third-party consumption less clear. Copying the full review script into every target repository would make updates and fixes expensive across repositories. A central hosted service could receive webhooks and post comments independently of Actions, but that introduces service hosting, queueing, storage, and secret management that are unnecessary for the current self-hosted runner requirement.

## Unresolved Questions

The exact GitHub UI text for app-authored reviews depends on the GitHub App name and generated bot account slug; creating the app as `Otter Reviewer` is the mechanism available through GitHub's identity model, but the bot login may still appear as a slugged app bot in some UI surfaces. The current implementation assumes one PR review job per repository event; future work could add stale-comment cleanup or review update semantics to avoid accumulating old comments across force pushes.
