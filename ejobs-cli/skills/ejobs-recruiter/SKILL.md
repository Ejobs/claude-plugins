---
name: ejobs-recruiter
description: Recruiter / company-side workflows on ejobs.ro — post and update jobs, review applicants, manage folders, check credits. Use when the user asks about publishing a job ad, screening candidates, or any company-account operation.
---

# eJobs — Recruiter workflows

The `ejobs-cli` binary is installed by this plugin at:

```
$HOME/.cache/ejobs-plugin/bin/ejobs-cli
```

Always call it via that full path (expand `$HOME` — it's not on `PATH`).
Every command supports `--output json`, `--describe`, `--fields`,
`--dry-run` for mutations.

## Three rules

1. **Discover before calling.** Use `--describe` on any subcommand before
   constructing arguments. Parent commands list their children too.
2. **Always `--output json`.**
3. **`--dry-run` every mutation first.** Show the user the validated payload,
   get confirmation, then rerun without `--dry-run`.

## Auth (company accounts)

Company accounts use a token-based flow, not the candidate OAuth browser
flow. Check status:

```
$HOME/.cache/ejobs-plugin/bin/ejobs-cli status --output json
```

If not logged in, the user must authenticate. Browser login works only in
local terminals. In Claude cowork / headless sessions, set `EJOBS_CLI_TOKEN`
before starting the session.

## Post a job

The payload is XML (legacy API). Two reference payloads are embedded below
so you can template from them instead of hitting `--describe` for every
field.

Always dry-run first:

```
$HOME/.cache/ejobs-plugin/bin/ejobs-cli company jobs create --xml @job.xml --dry-run --output json
```

Required fields: `type`, `company`, `title`, `departments`, `industries`,
`cities`, `job-types`, `career-levels`. Every catalog-ID field (department,
industry, city, career-level…) is resolvable via `--describe` which returns
a `catalog_url` pointing at the staticdata endpoint. **Always look up real
IDs — never hardcode.**

### Embedded template — create

```xml
<?xml version="1.0" encoding="utf-8"?>
<job version="1.1">
  <unique-id><![CDATA[my-internal-ref-001]]></unique-id>
  <date>2026-03-18</date>
  <type>989</type>
  <company><![CDATA[ACME Example SRL]]></company>
  <title><![CDATA[Professional driver]]></title>
  <positions>1</positions>
  <departments><department>31</department></departments>
  <industries><industry>19</industry></industries>
  <cities><city>1</city></cities>
  <job-types><job-type>8</job-type></job-types>
  <career-levels><career-level>4</career-level></career-levels>
  <required-experience><![CDATA[
    <p>Job description (HTML allowed).</p>
  ]]></required-experience>
</job>
```

Optional elements include `languages`, `education-levels`, `restrictions`,
`driving-license`, `salary`, `ideal-candidate`, `company-description`,
`interview/question`, `application-url`, and geo fields (`latitude`,
`longitude`, `adresa`, `accuracy`, `reper`). Check `--describe` for the
full set when a user asks for anything beyond the required minimum.

## Other recruiter workflows

- List jobs: `ejobs-cli company jobs list --output json`
- Get one: `ejobs-cli company jobs get --id <id> --output json`
- Update: `ejobs-cli company jobs update --id <id> --xml @update.xml --dry-run`
- Deactivate: `ejobs-cli company jobs deactivate --id <id> --dry-run`
- Applicants: `ejobs-cli company applicants list --job <id> --output json`
- Folders: `ejobs-cli company folders list --output json`
- Credits: `ejobs-cli company credits get --output json`
- Services: `ejobs-cli company services list --output json`

Use `--fields` to cut noise on list commands. Pagination defaults are
small on purpose — pass `--limit` explicitly for larger pulls.

## Error handling

Structured JSON on stderr with `code` values: `INVALID_INPUT` (2),
`AUTH_REQUIRED`/`AUTH_EXPIRED` (3), `NOT_FOUND` (4), `ACCOUNT_MISMATCH` (5).
Branch on `code`, not message text.
