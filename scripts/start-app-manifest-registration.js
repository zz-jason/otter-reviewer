#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const os = require("os");
const path = require("path");
const { execFileSync, spawn } = require("child_process");

const repo = process.argv[2] || "zz-jason/otter-review-test";
const account = process.argv[3] || "";
const [owner] = repo.split("/");
const appOwner = account || owner;
const state = crypto.randomBytes(18).toString("hex");
const privateKeyPath = path.join(os.homedir(), ".config", "otter-reviewer", "otter-reviewer.private-key.pem");

function gh(args, options = {}) {
  return execFileSync("gh", args, {
    ...options,
    encoding: options.encoding || "utf8",
    stdio: options.stdio || ["pipe", "pipe", "pipe"],
  });
}

function setSecret(name, value) {
  execFileSync("gh", ["secret", "set", name, "--repo", repo, "--body", value], {
    encoding: "utf8",
    stdio: ["pipe", "pipe", "pipe"],
  });
}

function html(title, body) {
  return `<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>${title}</title>
    <style>
      body { font-family: ui-sans-serif, system-ui, sans-serif; max-width: 760px; margin: 48px auto; line-height: 1.5; }
      code, pre { background: #f4f4f5; padding: 2px 5px; border-radius: 4px; }
      button, a.button { background: #1f883d; color: white; border: 0; padding: 10px 14px; border-radius: 6px; text-decoration: none; cursor: pointer; }
      .muted { color: #59636e; }
    </style>
  </head>
  <body>${body}</body>
</html>`;
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/"/g, "&quot;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function formPage(baseUrl) {
  const manifest = {
    name: "Otter Reviewer",
    url: "https://github.com/zz-jason/otter-reviewer",
    description: "Self-hosted Codex PR reviewer that posts inline comments as Otter Reviewer.",
    hook_attributes: {
      url: `${baseUrl}/webhook-disabled`,
      active: false,
    },
    redirect_url: `${baseUrl}/callback`,
    callback_urls: [`${baseUrl}/callback`],
    setup_url: `${baseUrl}/setup`,
    public: false,
    default_permissions: {
      contents: "read",
      pull_requests: "write",
    },
    default_events: [],
  };

  const action =
    appOwner === owner
      ? `https://github.com/settings/apps/new?state=${state}`
      : `https://github.com/organizations/${appOwner}/settings/apps/new?state=${state}`;

  return html(
    "Register Otter Reviewer",
    `<h1>Register Otter Reviewer</h1>
    <p>This page will create a GitHub App manifest for <code>${repo}</code>.</p>
    <form method="post" action="${action}">
      <input type="hidden" name="manifest" value="${escapeHtml(JSON.stringify(manifest))}">
      <button type="submit">Open GitHub App Registration</button>
    </form>
    <p class="muted">After GitHub creates the app, this local server will receive the one-time manifest code and install repo secrets.</p>`
  );
}

function callbackPage(url) {
  const code = url.searchParams.get("code");
  const returnedState = url.searchParams.get("state");
  if (!code) {
    return html("Missing code", "<h1>Missing manifest code</h1><p>GitHub did not return a code.</p>");
  }
  if (returnedState !== state) {
    return html("Invalid state", "<h1>Invalid state</h1><p>The returned state did not match this registration session.</p>");
  }

  const app = JSON.parse(gh(["api", "--method", "POST", `/app-manifests/${code}/conversions`]));
  if (!app.id || !app.pem) {
    throw new Error("GitHub did not return app id and PEM private key");
  }

  fs.mkdirSync(path.dirname(privateKeyPath), { recursive: true, mode: 0o700 });
  fs.writeFileSync(privateKeyPath, `${app.pem.trim()}\n`, { mode: 0o600 });
  setSecret("OTTER_REVIEWER_APP_ID", String(app.id));
  setSecret("OTTER_REVIEWER_PRIVATE_KEY", app.pem);

  const installUrl = `https://github.com/apps/${app.slug}/installations/new`;
  console.log(`\nCreated GitHub App ${app.slug} (${app.id}).`);
  console.log(`Wrote repo secrets OTTER_REVIEWER_APP_ID and OTTER_REVIEWER_PRIVATE_KEY to ${repo}.`);
  console.log(`Private key saved at ${privateKeyPath}.`);
  console.log(`Install URL: ${installUrl}\n`);

  return html(
    "Install Otter Reviewer",
    `<h1>App created</h1>
    <p>Secrets were installed into <code>${repo}</code>.</p>
    <p>Next, install the app on <code>${repo}</code>:</p>
    <p><a class="button" href="${installUrl}">Install Otter Reviewer</a></p>
    <p class="muted">Select only <code>${repo}</code> if GitHub asks for repository access.</p>`
  );
}

function setupPage(url) {
  const installationId = url.searchParams.get("installation_id");
  if (installationId) {
    setSecret("OTTER_REVIEWER_INSTALLATION_ID", installationId);
    console.log(`Installed OTTER_REVIEWER_INSTALLATION_ID=${installationId} in ${repo}.`);
  }

  return html(
    "Otter Reviewer Ready",
    `<h1>Otter Reviewer is ready</h1>
    <p>The GitHub App installation is configured for <code>${repo}</code>.</p>
    <p>You can now trigger the workflow:</p>
    <pre>gh workflow run "Otter Reviewer" --repo ${repo} -f pr_number=1</pre>`
  );
}

const server = http.createServer((req, res) => {
  try {
    const host = req.headers.host || "127.0.0.1";
    const url = new URL(req.url, `http://${host}`);
    let response;

    if (url.pathname === "/") response = formPage(`http://${host}`);
    else if (url.pathname === "/callback") response = callbackPage(url);
    else if (url.pathname === "/setup") response = setupPage(url);
    else response = html("Not found", "<h1>Not found</h1>");

    res.writeHead(url.pathname === "/webhook-disabled" ? 204 : 200, { "content-type": "text/html; charset=utf-8" });
    res.end(response);
  } catch (error) {
    console.error(error.stack || error.message || String(error));
    res.writeHead(500, { "content-type": "text/html; charset=utf-8" });
    res.end(html("Error", `<h1>Error</h1><pre>${String(error.stack || error.message || error)}</pre>`));
  }
});

server.listen(0, "127.0.0.1", () => {
  const { port } = server.address();
  const url = `http://127.0.0.1:${port}/`;
  console.log(`Open this URL in your browser to register Otter Reviewer:`);
  console.log(url);
  console.log(`\nWaiting for GitHub callback...`);

  const opener = process.platform === "darwin" ? "open" : "xdg-open";
  const child = spawn(opener, [url], { stdio: "ignore", detached: true });
  child.on("error", () => {});
  child.unref();
});
