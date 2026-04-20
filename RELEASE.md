# Releasing a new `ejobs-cli` version

The `ejobs-cli` Go source lives on GitLab at
`git.ejobs.ro/core/mono/ejobs-cli`. This repo (`Ejobs/claude-plugins`, on
GitHub) hosts the Claude Code plugin that pulls the compiled binaries at
session start.

## The flow (3 steps)

### 1. Build in `ejobs-cli`

From the `ejobs-cli` directory in the `mono` monorepo:

```bash
git tag ejobs-cli/v0.2.0
git push origin ejobs-cli/v0.2.0
VERSION=0.2.0 scripts/release.sh
```

Note the tag prefix: `mono` is a monorepo, so every subpackage namespaces
its GitLab tags (e.g. `ejobs-cli/v0.2.0`, `ejobs-qsm/v1.3.0`). This is
the Go standard for submodule versioning.

Output: `dist/` populated with binaries for darwin/amd64, darwin/arm64,
linux/amd64, linux/arm64, windows/amd64, plus `checksums.txt` and
`manifest.json`. Each binary embeds `0.2.0+<short-sha>` as its version
(verifiable via `ejobs-cli version`).

In production this will be wired into GitLab CI on tag push — the script
is vendor-agnostic so it drops straight into `.gitlab-ci.yml`.

### 2. Upload to this repo's GitHub Release

Tag convention: `cli-v<version>` (e.g. `cli-v0.2.0`). The plugin's
`download-binary.sh` resolves this tag at runtime.

```bash
gh release create cli-v0.2.0 \
  --repo Ejobs/claude-plugins \
  --title "ejobs-cli 0.2.0" \
  --notes "..." \
  dist/*
```

All five binaries plus `manifest.json` must be attached. The plugin reads
`manifest.json` to pick the right binary for the host's OS/arch and verify
sha256.

### 3. Trigger the plugin version bump

Send a `repository_dispatch` event to kick off the bump-PR workflow:

```bash
curl -X POST \
  -H "Authorization: Bearer $GITHUB_DISPATCH_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/Ejobs/claude-plugins/dispatches \
  -d '{"event_type":"ejobs-cli-release","client_payload":{"version":"0.2.0"}}'
```

The workflow at `.github/workflows/bump-cli.yml` opens a PR updating
`ejobs-cli/VERSION` and `ejobs-cli/.claude-plugin/plugin.json`. Review and
merge. On merge, users with marketplace auto-update enabled receive the
new plugin version automatically; the next session's `SessionStart` hook
detects the changed `VERSION` and downloads the new binary.

Manual fallback: trigger the same workflow via the Actions tab
(`workflow_dispatch`) with the target version.

## What end users do

Nothing, if they have marketplace auto-update enabled. Otherwise:

```
/plugin marketplace update ejobs-cli
/plugin update ejobs@ejobs-cli
```

## Secrets needed

- **On GitLab CI**: `GITHUB_DISPATCH_TOKEN` — a GitHub PAT (fine-grained,
  scoped to `Ejobs/claude-plugins`) with `contents:write` +
  `actions:write`. Used for the release upload and the dispatch call.
- **On GitHub Actions (this repo)**: nothing extra — the default
  `GITHUB_TOKEN` covers the PR creation via
  `peter-evans/create-pull-request`.
