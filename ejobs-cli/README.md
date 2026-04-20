# ejobs (plugin)

Claude Code plugin that bundles `ejobs-cli` plus skills for candidate and
recruiter workflows on [ejobs.ro](https://www.ejobs.ro).

## What it ships

- **`ejobs-cli` binary** — auto-downloaded on session start into
  `$CLAUDE_PLUGIN_DATA/bin/ejobs-cli`, version pinned by `VERSION`.
  Cached across sessions; sha256-verified against the release manifest.
- **`ejobs-candidate` skill** — auto-loads when the user talks about job
  search, CV editing, or applying.
- **`ejobs-recruiter` skill** — auto-loads for job posting, applicants,
  folders, credits.

No slash commands. The CLI's `--describe` output covers discovery; skills
teach the patterns. Natural-language intent ("list my CVs", "post this
job") is enough.

## Architecture

```
VERSION              ← pinned ejobs-cli version this plugin expects
hooks/hooks.json     ← SessionStart → scripts/download-binary.sh
scripts/
  download-binary.sh ← OS/arch-aware fetch, sha256 verify, cache under
                       $CLAUDE_PLUGIN_DATA/bin
skills/
  ejobs-candidate/   ← candidate workflows
  ejobs-recruiter/   ← recruiter workflows
```

## Upgrading the bundled CLI

1. Cut a new `ejobs-cli` release → builds binaries + `manifest.json`.
2. Upload binaries + `manifest.json` to this repo's GitHub Release at tag
   `cli-v<version>` (e.g. `cli-v0.2.0`).
3. Bump `VERSION` here + `version` in `.claude-plugin/plugin.json`.
4. Commit + push. Users with marketplace auto-update enabled receive it on
   next session; others run `/plugin marketplace update ejobs-cli` +
   `/plugin update ejobs@ejobs-cli`.

## Authentication

The CLI's OAuth browser flow only works in local terminals. For Claude
cowork / headless environments, set `EJOBS_CLI_TOKEN` before starting the
Claude session. The skills detect both paths and guide the user
accordingly.
