# ejobs (plugin)

Claude Code plugin that bundles `ejobs-cli` plus skills for candidate and
recruiter workflows on [ejobs.ro](https://www.ejobs.ro).

## What it ships

- **`ejobs-cli` binary** — auto-downloaded on `SessionStart` into
  `$HOME/.cache/ejobs-plugin/bin/`, version pinned by `VERSION`. Cached
  across sessions, sha256-verified against the release manifest, and
  added to Claude's Bash-tool `PATH` via `CLAUDE_ENV_FILE` so Claude can
  invoke it as a bare `ejobs-cli` command.
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
                       $HOME/.cache/ejobs-plugin/bin, and PATH export
                       to Claude via CLAUDE_ENV_FILE
skills/
  ejobs-candidate/   ← candidate workflows
  ejobs-recruiter/   ← recruiter workflows
```

## Getting updates

Users with marketplace auto-update enabled receive new versions on next
session. Otherwise:

```
/plugin marketplace update ejobs-cli
/plugin update ejobs@ejobs-cli
```

The next `SessionStart` detects the changed `VERSION` and downloads the
matching binary.

## Authentication

The CLI's OAuth browser flow only works in local terminals. For Claude
cowork / headless environments, set `EJOBS_CLI_TOKEN` before starting the
Claude session. The skills detect both paths and guide the user
accordingly.
