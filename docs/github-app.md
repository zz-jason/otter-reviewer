# GitHub App Setup

Create one GitHub App and install it on every repository that should use Otter Reviewer.

`docs/github-app-manifest.json` contains the app manifest values for this setup. GitHub still requires completing the app creation flow in the browser, but the manifest captures the app name, disabled webhook, and repository permissions.

After GitHub redirects with a one-time `code`, install the app secrets into a target repository with:

```bash
./scripts/install-app-secrets-from-manifest-code.sh owner/repo "$code"
```

## App identity

- App name: `Otter Reviewer`
- Homepage URL: `https://github.com/zz-jason/otter-reviewer`
- Webhook: disabled for the workflow-driven setup

GitHub review comments are authored by the credential used for the API call. Otter Reviewer posts reviews with this app's installation token, so GitHub surfaces the app identity instead of `github-actions[bot]`.

## Repository permissions

- `Contents`: read
- `Pull requests`: read and write
- `Metadata`: read, granted automatically

No account permissions are required.

## Secrets

Add these as repository secrets or selected-repository organization secrets:

- `OTTER_REVIEWER_APP_ID`: the numeric app ID from the app settings page
- `OTTER_REVIEWER_PRIVATE_KEY`: a generated private key PEM for the app
- `OTTER_REVIEWER_INSTALLATION_ID`: optional; the CLI can resolve the installation from `owner/repo`

The private key can be stored as a multi-line PEM, escaped `\n` text, or base64-encoded PEM.
