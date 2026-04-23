# repo-pulse — specification

Status: **design** (not yet implemented).
Plugin version targeted: `0.1.0`.

## Purpose

Give the user a fast, reliable summary of what changed in the current git
repository since they were last active. The target user works across ~8
different repositories, frequently context-switches, and wants two things:

1. Catch up on colleagues' activity after a break of a few days
2. Avoid duplicating work that was already pushed to a remote branch by
   someone else (or themselves on another machine)

Merge-request review load is informational, not the primary driver.

## Scope

- **Current repository only.** The plugin does not know about other repos.
  Cross-repo dashboards are explicitly out of scope; a sibling plugin can add
  that later if needed.
- **GitLab-first.** Remote-side data is fetched via `glab`. If the repository
  is not on GitLab, the `glab`-dependent sections are skipped with a warning;
  the git-only sections still run.
- **Read-only.** The plugin never mutates the repository, only `git fetch`
  is executed as a side effect.

## Invocation

Slash command (name is the skill name, namespaced by the plugin):

```
/repo-pulse:whats-new [--since=<period>]
```

The skill also auto-invokes on natural-language prompts such as "what's new
in this repo", "catch me up", "what did the team do while I was away". This
is controlled by the `description` field in `SKILL.md`.

### Arguments

| Argument | Default | Behavior |
|---|---|---|
| `--since=<period>` | *smart* (see below) | Any value `git log --since` accepts: `3d`, `1w`, `2026-04-20`, `"2 weeks ago"`, etc. |

Smart default: find the most recent commit across all refs whose author email
matches any entry in the effective email list (see `Configuration` below).
Use that commit's **committer date** as the window start — not the author
date, because rebases and cherry-picks preserve author date and would make
the window jump backwards across replays. If no such commit exists in this
repo, or the effective email list is empty, fall back to `default_since`
from the plugin user config (default: `7 days ago`).

All time comparisons throughout the plugin use committer date, for
consistency with this smart default.

## Configuration

All user-tunable values flow through Claude Code's `userConfig` block in
`.claude-plugin/plugin.json`. The harness prompts for them on first enable,
stores them in `~/.claude/settings.json` under
`pluginConfigs."repo-pulse".options`, and exposes them to the script as
`CLAUDE_PLUGIN_OPTION_<KEY>` environment variables. Values survive `/plugin
update` because `settings.json` is outside the plugin cache.

The plugin declares exactly two fields:

| Field | Type | Default | Purpose |
|---|---|---|---|
| `extra_emails` | `string`, `multiple: true` | `[]` | Additional author emails beyond `git config user.email`. For old/personal addresses you've also committed with. |
| `default_since` | `string` | `"7 days ago"` | Fallback window when the smart default can't resolve a last-commit anchor. |

The effective email list is constructed at runtime as:

```
EFFECTIVE_EMAILS = dedupe_case_insensitive(
  [ git config user.email ]  ∪  extra_emails
)
```

Zero-config first run: in any repo where `git config user.email` is set
(which is always, for any repo you've committed to), `extra_emails` can
stay empty and the plugin works immediately.

Default branch is auto-detected via `git symbolic-ref refs/remotes/origin/HEAD`
with `main` as a last-resort fallback; it is not configurable.

### Dev-mode fallback (optional)

When running under `claude --plugin-dir ...`, the Claude Code harness may
not populate `CLAUDE_PLUGIN_OPTION_*` env vars. If so, the script falls
back to sourcing a user-authored `skills/whats-new/config.local.sh` that
declares a plain bash array:

```bash
# skills/whats-new/config.local.sh (gitignored, dev-only)
EXTRA_EMAILS=(
  "you@example.com"
  "you@company.com"
)
# DEFAULT_SINCE="14 days ago"   # optional
```

This file is **not** shipped with the plugin and **not** read when the
plugin is installed via `/plugin install`. It is a local convenience for
`--plugin-dir` sessions. The script emits `> note: dev-mode: …` whenever
the fallback activates so the user can tell which config path applied.

## Data Collected

The script produces six sections. Sections with zero items are omitted from
the output; a single-line "Nothing new" summary is printed only if every
section is empty.

### 1. Merged to default branch

Commits reachable from `origin/<default>` whose committer time is within the
window, authored by someone other than the user. Shows short SHA, date,
author (name), first line of message.

Query: `git log origin/<default> --since=<T> --no-merges --format=...`
post-filtered against the effective email list.

### 2. New / updated remote branches

Remote branches (under `refs/remotes/origin/`) whose last commit time is
within the window, excluding:

- The default branch
- Branches whose every commit in the window is by the user

For each branch: name, last committer (name), last commit time, commits
ahead of default branch.

Query: `git for-each-ref refs/remotes/origin/ --sort=-committerdate
--format='%(refname:short) %(committerdate:iso-strict) %(authoremail)'` and
post-filter.

The script does not do WIP-similarity detection itself; that is Claude's
job in the TL;DR step (see Data Flow). This keeps the script deterministic
and free of heuristics.

### 3. Merge requests

Uses `glab mr list` with `--updated-after` when supported, otherwise the
full JSON via `glab mr list -F json` filtered by `updated_at` in the
script. Split into three subsections:

- **Open — others.** Authored by someone else, still open.
- **Merged this period.** Any author, merged within window.
- **Open — mine.** Authored by the user, still open.

Each entry: `!<iid> <title> — <author>, <source> → <target>, CI: <status>`.

### 4. My activity

Commits across all refs authored by any address in the effective email list,
within the window. Groups by branch, then by date. Shows SHA, time, branch,
message.

Query: `git log --all --since=<T> --extended-regexp --author=<regex>` with
regex built as an OR-join of the effective email list.

### 5. Merge requests awaiting my review

`glab mr list --reviewer=@me` (no time filter — if it's outstanding, show
it). Entries: `!<iid> <title> — <author>, age: <N days>`.

### 6. Default branch CI status

Last pipeline on `origin/<default>` — id, status, created_at, web URL. One
line.

## Output Format

Plain markdown to stdout. Structure:

```markdown
# What's new in <repo-slug>

Window: <ISO start> → <ISO end> (<reason>)
# <reason> is one of:
#   "from your last commit on <ISO date>"   — smart default succeeded
#   "--since=<value>"                        — explicit flag from the user
#   "DEFAULT_SINCE fallback (<value>)"       — no user commits found

## Merged to `<default>` (N)
- YYYY-MM-DD `sha` **message** — Author Name
- ...

## New / updated branches (N)
- `branch-name` — last push YYYY-MM-DD by Author (M commits ahead of <default>)
- ...

## Merge requests
### Open — others (N)
- !1234 **title** — Author, source → target, CI: ✅
- ...

### Merged this period (N)
- ...

### Open — mine (N)
- ...

## My activity (N commits)
- ...

## MRs awaiting my review (N)
- ...

## CI on `<default>`
- #<pipeline-id> <status> — YYYY-MM-DD HH:MM (<url>)
```

Section order is fixed. The plugin does not produce JSON in v0.1.0.

## Data Flow

```
/repo-pulse:whats-new [--since=X]
        │
        ▼
SKILL.md tells Claude:
  1. Run bash: ${CLAUDE_PLUGIN_ROOT}/skills/whats-new/scripts/whats-new.sh [--since=X]
  2. Read the markdown output
  3. Add a 1–3 bullet TL;DR above it highlighting whatever matters most
     (e.g. branches with names similar to the user's current WIP, stale
     open MRs, failing CI on default)
  4. Answer follow-ups conversationally
        │
        ▼
whats-new.sh:
  a. read CLAUDE_PLUGIN_OPTION_* env vars (or dev-mode fallback)
  b. preflight: in a git repo? gitlab origin? glab authed?
  c. git fetch --all --prune --quiet  (warn on failure, continue)
  d. resolve window start (from --since OR smart default)
  e. collect sections 1–6 in parallel where safe
  f. emit markdown to stdout
```

## Error Handling

| Condition | Behavior |
|---|---|
| Not in a git work tree | Print a one-line error to stderr, exit 1 |
| Origin is not GitLab | Print a warning header; run sections 1, 2, 4 only |
| `glab auth status` fails | Same as above — git-only sections |
| `git fetch` fails (offline) | Print warning, continue against stale refs |
| Window start cannot be resolved and `DEFAULT_SINCE` is invalid | Print warning, fall back to `7 days ago` literal |
| `jq` not installed, origin is GitLab | Exit 1 with install hint — `jq` is required to parse `glab` JSON |
| `jq` not installed, origin is not GitLab | Warn, skip glab-dependent sections (same path as non-gitlab origin) |

All warnings render as the first line(s) of the output prefixed with
`> note:` so Claude surfaces them to the user without interpreting them as
real data.

## File Layout

```
repo-pulse/
├── .claude-plugin/
│   └── plugin.json
├── SPEC.md
├── README.md
└── skills/
    └── whats-new/
        ├── SKILL.md
        └── scripts/
            ├── whats-new.sh         # entry point (chmod +x)
            └── lib/                 # shared helpers, if the main script grows
                ├── sections.sh
                └── format.sh
```

`lib/` is optional; introduce only when `whats-new.sh` exceeds ~200 lines.

## SKILL.md Sketch

```yaml
---
name: whats-new
description: Summarize what changed in the current git repository since the user was last active. Shows merged commits on the default branch, new or updated remote branches, open and merged MRs on GitLab, the user's own recent commits, MRs awaiting review, and CI status on the default branch. Use when the user asks "what's new", "catch me up", "what did the team do", or returns to a repo after an absence.
argument-hint: [--since=<period>]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/whats-new/scripts/whats-new.sh:*), Bash(git:*), Bash(glab:*)
---
```

The body of SKILL.md instructs Claude to:

1. Run the script and read its markdown stdout.
2. Prepend a 1–3 bullet TL;DR highlighting whatever matters most (branches
   similar to the user's current WIP, stale open MRs, failing CI on
   default).
3. Answer follow-up questions conversationally using `git` and `glab`
   directly.

`Bash(git:*)` and `Bash(glab:*)` are in `allowed-tools` specifically for
step 3 — e.g. "show me the diff for that branch" or "what's in !1234" — so
follow-ups do not trigger extra permission prompts. The main summary itself
comes entirely from the script.

## Testing

Manual acceptance, no CI. Run against three repositories covering the
relevant cases:

1. **`promin/funnels-builder`** — gitlab, author is the user, multiple
   collaborators. Expected: all six sections populated.
2. A **GitHub repo** — non-gitlab origin. Expected: warning header, then
   git-only sections.
3. **Empty window** — run immediately after a run with no new activity.
   Expected: single-line "Nothing new since `<T>`".

Each acceptance pass is logged informally in a PR description or commit
body.

## Non-Goals For v0.1.0

- Cross-repository aggregation
- Caching state between runs (no `${CLAUDE_PLUGIN_DATA}` writes in v0.1.0)
- GitHub support via `gh`
- Slack / email notifications
- JSON output mode
- Configurable section order or per-section toggles
- Detecting comments on the user's MRs (section 5 only covers assignment)
- Stale-branch cleanup hints

Each of these can be added later as a separate change once the core workflow
is proven in daily use.
