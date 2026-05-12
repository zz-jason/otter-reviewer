# Otter Reviewer AI PR Review

- Co-Authored-By: Codex CLI, GPT-5
- Date: 2026-05-12

## Summary

Otter Reviewer is a reusable AI pull request review system that runs on self-hosted GitHub Actions runners, invokes Codex using the runner's existing `CODEX_HOME/config.toml`, and posts inline review comments through a GitHub App named `Otter Reviewer`. The implementation is split into a central `otter-reviewer` repository containing the CLI, composite action, reusable workflow, runner scripts, and setup docs, while target repositories only add a small workflow and GitHub App secrets. Posting with a GitHub App installation token is required so GitHub displays the review author as the app identity rather than `github-actions[bot]`.

## Background

The prior experiment proved that a self-hosted runner can execute Codex and post inline review comments on a PR. It also exposed two product requirements for a durable implementation: the visible GitHub reviewer must not be `github-actions[bot]`, and onboarding additional repositories must be cheap. GitHub Actions' default `GITHUB_TOKEN` always attributes API-created reviews to `github-actions[bot]`, so Otter Reviewer must use a different credential class. A GitHub App is the right boundary because it has a named app identity, per-repository installation scope, revocable private-key credentials, and narrowly scoped permissions for pull request review creation. The users are repository owners who want Codex-based review on PRs without copying review logic into every codebase.

## Detailed Design

The system has four components. First, a self-hosted runner runs either on the host or in Docker with labels such as `self-hosted` and `otter-reviewer`; it provides `codex`, `git`, `node`, and the same `~/.codex/config.toml` already used by local Codex. Second, each target repository adds `.github/workflows/otter-review.yml`, which calls `zz-jason/otter-reviewer/.github/workflows/review.yml@main`. Third, the reusable workflow checks out the PR head and invokes the composite action in this repository. Fourth, `bin/otter-reviewer.js` performs the actual review and GitHub API calls.

The review flow is:

```text
pull_request event
  -> target repo workflow
  -> self-hosted runner labeled otter-reviewer
  -> reusable workflow checkout
  -> otter-reviewer action
  -> GitHub App JWT
  -> installation access token for target repo
  -> git diff base...head
  -> codex exec with structured JSON schema
  -> validate/filter comments to valid RIGHT-side diff lines
  -> POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews
```

The GitHub App named `Otter Reviewer` needs `Contents: read`, `Pull requests: read and write`, and the automatic `Metadata: read` permission. The workflow passes `OTTER_REVIEWER_APP_ID` and `OTTER_REVIEWER_PRIVATE_KEY` as secrets. The CLI signs a short-lived RS256 JWT, resolves the app installation for the current repository unless `OTTER_REVIEWER_INSTALLATION_ID` is set, creates an installation token, and uses that token for PR metadata and review creation. This is the identity mechanism that changes GitHub attribution from `github-actions[bot]` to the app.

Codex output is constrained by `schema/codex-review.schema.json`, which requires a summary plus an array of `{path, line, body, severity}` comments. The CLI still treats model output as untrusted: it extracts JSON defensively, normalizes comment fields, deduplicates comments, truncates oversized bodies, and drops any comment whose path and line do not map to a RIGHT-side line in the PR diff. This prevents GitHub API failures caused by comments on invalid diff lines.

Target repository configuration stays small. A repo can use the template workflow directly, override runner labels with `runs-on`, set `max-inline-comments`, and optionally add `.otter-reviewer.md` for local review instructions. `scripts/configure-target-repo.sh owner/repo` installs or updates the workflow through `gh` without requiring a local clone, and it can set app secrets from environment variables. Organization-level secrets can make onboarding additional repositories a workflow-copy operation plus GitHub App installation.

Failure cases are explicit. If no PR number exists, the CLI exits successfully without posting. If the diff is empty, it skips. If Codex returns no valid comments and `post-empty-review` is false, it skips. If the GitHub App is not installed or lacks permissions, token creation or review posting fails the job. If the runner cannot reach the Codex provider configured in `CODEX_HOME/config.toml`, the Codex step fails and the job surfaces that as a runner environment issue.

## Alternative Designs Considered

Using `GITHUB_TOKEN` is simpler but cannot meet the identity requirement because reviews are attributed to `github-actions[bot]`. A bot user's personal access token could show a custom user display name, but it is broader, harder to scope per repository, and weaker operationally than a GitHub App. Copying the full review script into every target repository would avoid private reusable workflow access constraints, but it would make updates and fixes expensive across repositories. A central hosted service could receive webhooks and post comments independently of Actions, but that introduces service hosting, queueing, storage, and secret management that are unnecessary for the current self-hosted runner requirement.

## Unresolved Questions

The exact GitHub UI text for app-authored reviews depends on the GitHub App name and generated bot account slug; creating the app as `Otter Reviewer` is the mechanism available through GitHub's identity model, but the bot login may still appear as a slugged app bot in some UI surfaces. Private reusable workflow access may need repository or organization Actions settings depending on where `otter-reviewer` is hosted. The current implementation assumes one PR review job per repository event; future work could add stale-comment cleanup or review update semantics to avoid accumulating old comments across force pushes.
