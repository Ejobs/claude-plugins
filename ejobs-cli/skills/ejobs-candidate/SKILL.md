---
name: ejobs-candidate
description: Candidate-side workflows on ejobs.ro — search jobs, view and edit your CV, manage applications. Use when the user asks about finding a job, improving their CV, updating profile details, or applying.
---

# eJobs — Candidate workflows

The `ejobs-cli` binary is auto-installed by this plugin's `SessionStart`
hook and added to Claude's Bash-tool `PATH`. Invoke it as a bare command:

```
ejobs-cli <subcommand> --output json
```

If `ejobs-cli` is not found, start a fresh Claude Code session — the hook
runs once per session and caches the binary for the pinned `VERSION`.

Every command
supports `--output json`, `--describe`, `--fields`, `--dry-run` (mutations).

## Three rules for using this CLI

1. **Discover before calling.** When you don't know a subcommand's parameters
   or payload shape, run:
   ```
   ejobs-cli <subcommand> --describe
   ```
   The output is authoritative — do not guess flag names.

2. **Always request JSON.** Pass `--output json` on every call so your
   downstream parsing is deterministic:
   ```
   ejobs-cli candidate cv get --output json
   ```

3. **Resolve catalog IDs at runtime.** Fields with `"input": "catalog"` in
   `--describe` include a `catalog_url`. Fetch that URL with `curl` to get
   the real IDs instead of guessing or hallucinating. Example:
   ```
   curl -s 'https://api.ejobs.ro/cities?pageSize=10000'
   ```

## Auth

Before any authenticated call, check status:

```
ejobs-cli status --output json
```

If `logged_in` is `false`, the user needs to authenticate. Two paths:

- **Interactive (local terminal):** ask the user to run
  `ejobs-cli login` in their terminal. The command
  opens a browser and pastes a code back.
- **Headless (Claude cowork, CI, any no-browser env):** the user must set
  `EJOBS_CLI_TOKEN` in their environment before starting the session.

Do not attempt to drive the browser login flow from inside Claude Code.

## Common candidate workflows

### View CV
```
ejobs-cli candidate cv get --output json
```

### Update CV (dry-run first)
Always run with `--dry-run` first, show the user the diff, confirm, then
apply. Payload shape comes from `--describe`:

```
ejobs-cli candidate cv update --describe
```

### Search jobs
```
ejobs-cli jobs list --describe
ejobs-cli jobs list --output json --fields id,title,company,city
```

Use `--fields` aggressively to keep result sets small — a raw `jobs list`
call can return hundreds of items.

## Error handling

Errors are JSON on stderr: `{"error": "...", "code": "...", "details": {...}}`.
Distinct exit codes: 1 general, 2 invalid input, 3 auth, 4 not found, 5
permission. Use the `code` string (not the message) for branching.
