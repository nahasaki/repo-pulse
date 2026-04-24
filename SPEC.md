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
- **GitHub and GitLab supported.** Remote-side data is fetched via `gh` on
  GitHub origins, `glab` on GitLab origins. The forge is auto-detected from
  the origin URL (fast path) with a local `auth status --hostname <h>` probe
  fallback for GitHub Enterprise and self-hosted GitLab. Unknown forges
  (Gitea, Codeberg, etc.) fall through silently to git-only sections.
- **Read-only.** The plugin never mutates the repository, only `git fetch`
  is executed as a side effect.

See §Error Handling for the behavior when the forge CLI is missing or
unauthenticated (short answer: the script emits a multi-line install hint
and runs the git-only sections).
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

The plugin declares five fields:

| Field | Type | Default | Purpose |
|---|---|---|---|
| `extra_emails` | `string`, `multiple: true` | `[]` | Additional author emails beyond `git config user.email`. For old/personal addresses you've also committed with. |
| `default_since` | `string` | `"7 days ago"` | Fallback window when the smart default can't resolve a last-commit anchor. |
| `summary_mode` | `string` (enum `auto` / `off` / `always`) | `"auto"` | Controls the `## Themes this period` section. `auto` uses the threshold engine. `off` skips themes entirely (pre-0.4.0 output). `always` forces the parallel-subagent path even on quiet repos. |
| `summary_max_commits` | `string` (integer-valued) | `"50"` | Hard safety cap. When the post-filter eligible-commit count exceeds this, themes are skipped with a `> note:` advising to narrow the window. |
| `summary_model` | `string` (enum `haiku` / `sonnet` / `opus` / `inherit`) | `"haiku"` | Model for `Task` subagents in parallel-mode theme summarization. **Parallel-only**: serial-mode summarization always uses the host Claude Code session's model — this value does not affect it. On an unrecognized value, falls back to `inherit` and emits a `> note:`. |

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

### 3. Merge requests / Pull requests

Forge-aware; output structure is identical across forges, only the number
prefix changes.

- GitLab: `glab mr list -A -F json --per-page 100`, filtered in jq by
  `updated_at` / `merged_at`. Number prefix `!<iid>`, trailing column
  `CI: <pipeline-status>`.
- GitHub: `gh pr list --state=all --json number,title,author,headRefName,
  baseRefName,state,createdAt,updatedAt,mergedAt,statusCheckRollup
  --limit 100`, filtered in jq. Number prefix `#<number>`, trailing column
  `checks: <rollup>` where rollup is summarized to `success | failure |
  pending | mixed | —` based on the status-check states.

Three subsections:

- **Open — others.** Authored by someone else, still open.
- **Merged this period.** Any author, merged within window.
- **Open — mine.** Authored by the user, still open.

Each entry: `<prefix> <title> — <author>, <source> → <target>, <ci-column>`.

### 4. My activity

Commits across all refs authored by any address in the effective email list,
within the window. Groups by branch, then by date. Shows SHA, time, branch,
message.

Query: `git log --all --since=<T> --extended-regexp --author=<regex>` with
regex built as an OR-join of the effective email list.

### 5. MRs / PRs awaiting my review

No time filter — if it's outstanding, show it.

- GitLab: `glab mr list --reviewer=@me -F json`. Entries:
  `!<iid> <title> — <author>, age: <N days>`.
- GitHub: `gh search prs --review-requested=@me --state=open --json …`
  (cross-repo search — mirrors GitLab's across-projects semantics). Entries:
  `#<number> <title> — <author>, age: <N days> [<owner>/<repo>]`.

### 6. Default branch CI status

Latest CI run on `origin/<default>`. Adaptive label:

- GitLab: `- #<pipeline-id> <status> — YYYY-MM-DD HH:MM (<web-url>)`.
- GitHub: `- <workflow-name> #<run-id> <status-or-conclusion> — YYYY-MM-DD
  HH:MM (<url>)` — `conclusion` used when `status=="completed"`, else the
  raw status (e.g., `in_progress`).

## Output Format

The user-visible output is **prose**. The skill composes 1–4 prose
paragraphs from the script's internal scratch output (which is still
the six-section markdown described below under §Script internal
output). Paragraphs with no source data are omitted.

Shape:

```markdown
# What's new in <repo-slug>

Window: <ISO start> → <ISO end> (<reason>)
# <reason> is one of:
#   "from your last commit on <ISO date>"   — smart default succeeded
#   "--since=<value>"                        — explicit flag from the user
#   "DEFAULT_SINCE fallback (<value>)"       — no user commits found

<Shipped paragraph — what the team merged>

<In flight paragraph — active PRs and branches, with collision heads-up if applicable>

<Needs you paragraph — reviews awaiting you, failing CI>

<You paragraph — your own recent activity>
```

Paragraph roles:

| Role | Source in script output | Include when |
|------|--------------------------|--------------|
| Shipped | §1 Merged + §3 Merged-this-period | Any merged work in-window |
| In flight | §2 New branches + §3 Open — others + collision flags | Any open PRs or new branches |
| Needs you | §5 Awaiting my review + §6 CI failures | Any review-due or CI-red items |
| You | §4 My activity | User has commits in-window |

Role order is fixed. Empty paragraphs are omitted without a divider.
No numeric totals appear in prose (no "22 commits", no "5 branches").
PR and branch references are rendered as markdown links per
§Link rendering.

When every source section is empty, the skill passes the script's
`Nothing new since <ISO>` single line through without rendering a
header or paragraphs.

### Shipped paragraph composition

The Shipped paragraph is composed from:

- §1 commits → grouped into clusters by (author, conventional-
  commit-type, top-level-path) — see §Themes filtering.
- §3 merged-this-period PRs → surfaced in the same cluster framework
  when their commits overlap §1 (forge-dependent).
- Subagent-derived one-or-two-sentence clauses stitched into
  flowing prose by the host session.

Under `summary_mode: off`, no diff reads happen; the paragraph
degrades to subject/title-level prose. The paragraph still renders.

### In flight paragraph composition

Summarizes §2 and §3 "Open — others" entries. When collisions fire
(see §Collision detection), the paragraph includes a **heads-up**
phrase explicitly calling out the collision. When there are many
open PRs (10+), the paragraph highlights 3–5 most notable and
summarizes the rest (e.g., "and a handful of dependency bumps").

### Needs you paragraph composition

Combines §5 (reviews awaiting) with §6 failures and any `prs_open_mine`
entries with red checks. If none of those have content, the
paragraph is omitted.

### You paragraph composition

Brief, informational — the user knows what they did. Describes the
arc of their §4 activity (e.g., "You shipped the v0.4.0 themes
release and fixed the marketplace schema.").

### Collision detection

Before composing the In flight paragraph, the skill builds two sets:

```
MY_BRANCHES    = §4 my_activity branches
               ∪ `git branch --list` output
               ∪ current HEAD branch

THEIRS_BRANCHES = §3 Open — others source branches
               ∪ §2 new/updated remote branches
```

For each `(mine, theirs)` pair, flag a collision when either:

1. **Name overlap**: `theirs` shares ≥ 3 consecutive characters with
   `mine` after lowercasing, and the shared substring is not in
   `{main, master, develop, dev, trunk, fix, feat, feature, chore,
   docs, test, wip}`.
2. **Path overlap + conventional-commit match**: the user's most
   recent commit on `mine` touches top-level path `P`, an open PR
   with source `theirs` has `P` as a file prefix, AND both the
   user's commit subject and the PR title share the same
   conventional-commit type (`feat:` / `fix:` / etc.).

When triggered, the In flight paragraph emits a heads-up phrase,
e.g., *"Heads-up: Sam's open [#13266] touches the same skill-install
area as your branch `fix-skill-install`."*

The heuristic is conservative — false positives acceptable, false
negatives are the failure mode. Users are the judge.

### Link rendering

References inside the prose are rendered as GitHub-Flavored Markdown
links clickable in Claude Code's terminal renderer. No OSC 8 escape
sequences are emitted.

URL construction reads `git remote get-url origin`, handles HTTPS
and SSH, strips the `.git` suffix, and derives `<host>/<owner>/<repo>`.

| Reference | GitHub | GitLab |
|-----------|--------|--------|
| PR / MR | `[#<N>](https://<host>/<owner>/<repo>/pull/<N>)` | `[!<iid>](https://<host>/<owner>/<repo>/-/merge_requests/<iid>)` |
| Branch | `` [`<branch>`](https://<host>/<owner>/<repo>/tree/<branch>) `` | `` [`<branch>`](https://<host>/<owner>/<repo>/-/tree/<branch>) `` |
| Commit | `` [`<sha>`](https://<host>/<owner>/<repo>/commit/<sha>) `` | `` [`<sha>`](https://<host>/<owner>/<repo>/-/commit/<sha>) `` |

On unknown forge, emit plain text instead: `#<N>`, `` `<branch>` ``,
`` `<sha>` ``. Info stays; only the link wrapper is omitted.

## Script internal output

The shell script continues to emit structured markdown (the six
sections described below) plus a `<!-- themes-metadata -->` HTML
comment. This is **the skill's internal scratch**, not the user-
visible output. The skill parses it and composes prose.

Users who want the old structured view can run the script directly:
`${CLAUDE_PLUGIN_ROOT}/skills/whats-new/scripts/whats-new.sh`. The
output contract for that direct invocation is:

```markdown
# What's new in <repo-slug>
Window: <ISO start> → <ISO end> (<reason>)

## Merged to `<default>` (N)
- YYYY-MM-DD `sha` **message** — Author Name

## New / updated branches (N)
- `branch-name` — last push YYYY-MM-DD by Author (M commits ahead of <default>)

## Merge requests
### Open — others (N)
- !1234 **title** — Author, source → target, CI: <status>
### Merged this period (N)
### Open — mine (N)

## My activity (N commits across M branches)
- **<branch>**
  - YYYY-MM-DD HH:MM `sha` **subject**

## MRs awaiting my review (N)
- !1234 **title** — Author, age: N days

## CI on `<default>`
- #<pipeline-id> <status> — YYYY-MM-DD HH:MM (<url>)

<!-- themes-metadata
sha,author_name,added,deleted,files
...
-->
```

### Themes filtering

Before inclusion in the Shipped paragraph's cluster input, commits
are filtered out (they still contribute to the Shipped paragraph at
subject-level — filtering only excludes them from
cluster-and-summarize):

- Bot authors — author name ends with `[bot]`.
- Lock/vendor-only changes — every file matches `*.lock` / `go.sum` /
  `package-lock.json` / `yarn.lock` / `Cargo.lock` / `vendor/**` /
  `node_modules/**`.
- Trivial dep bumps — subject matches `^chore(\(deps\))?: bump `
  AND shortstat additions ≤ 5.
- Pure merge commits — ≥ 2 parents AND empty cross-parent diff.
- Docs-only changes — every file matches `*.md` / `docs/**` /
  `README*` / `LICENSE*`.

Filter evaluation is conservative: if any file in a commit sits
outside every exclusion pattern, the commit is NOT filtered.

### Threshold dispatcher

| Mode | Condition | Behavior |
|------|-----------|----------|
| `skip` | `N == 0`, OR `N > summary_max_commits` | Shipped paragraph composes from subjects only; no diff reads. Emit `> note:` when skipped due to cap. |
| `degraded` | `summary_mode == "off"` | Same as `skip` plus no cap note — Shipped paragraph degrades but renders. |
| `serial` | `summary_mode == "auto"` AND `N ≤ 10` AND `DIFF_KB ≤ 50` | Skill reads diffs in the host session to generate subagent-equivalent clauses. |
| `parallel` | `summary_mode == "always"`, OR `auto` when `serial` doesn't qualify | Spawn subagents via `Task` tool, ≤ 8 concurrent, one per cluster. |

`N` = eligible commits after filtering. `DIFF_KB` ≈ Σ(added lines) ÷
20. Constants (`10`, `50`, `8`) live as named thresholds near the top
of SKILL.md and are starting defaults — retune only via a new
OpenSpec change.

If ≥ 25% of parallel subagents fail, the skill prepends a
`> note: themes partially degraded: <k> of <n> clusters failed to
summarize` line above the narrative output (below the header).

### Summarizer model selection (parallel mode only)

The `summary_model` userConfig value (default `haiku`) determines the
model for parallel-mode subagents. The skill passes the value to the
`Task` tool's `model` parameter; when the value is `inherit`, the
parameter is omitted so subagents follow the host Claude Code
session. Unknown values fall back to `inherit` with a `> note:`.

This knob does **not** affect serial mode. Serial-mode
summarization runs inline in the host session and uses whatever
model the user picked for that session. Users who want the
cheap-by-default Haiku pass on every invocation can combine
`summary_model: haiku` with `summary_mode: always` — the latter
forces the parallel code path regardless of commit volume.

## Data Flow

```
/repo-pulse:whats-new [--since=X]
        │
        ▼
SKILL.md tells Claude:
  1. Run bash: ${CLAUDE_PLUGIN_ROOT}/skills/whats-new/scripts/whats-new.sh [--since=X]
  2. Narrative pipeline:
       A. Fact-extraction — parse §1–§6 + <!-- themes-metadata -->
          from the script's markdown into per-role fact buckets.
       B. URL base derivation — git remote get-url origin → host/owner/repo.
       C. Diff reads for Shipped paragraph — threshold engine picks
          serial (host-session reads) or parallel (Task subagents,
          model controlled by summary_model). Degraded under summary_mode: off.
       D. Collision detection — build MY_BRANCHES vs THEIRS_BRANCHES;
          apply name-overlap and path-overlap rules; flag matches.
       E. Paragraph composition — Shipped → In flight → Needs you → You;
          empty paragraphs omitted.
       F. Link rendering — wrap PR/branch/commit refs in markdown links
          (plain text on unknown forge).
       Emit header + composed prose; strip the metadata block and any
       §-headings from the script's scratch output.
  3. Answer follow-ups conversationally
        │
        ▼
whats-new.sh:
  a. read CLAUDE_PLUGIN_OPTION_* env vars (or dev-mode fallback)
  b. detect forge: URL-match github.com/gitlab.com, else probe
     `gh/glab auth status --hostname <h>` (local only, parses stdout)
  c. preflight: in a git repo? forge CLI available + authed?
     missing CLI → multi-line `> note:` install hint
  d. git fetch --all --prune --quiet  (warn on failure, continue)
  e. resolve window start (from --since OR smart default)
  f. collect sections 1–6 in parallel, dispatching §3/§5/§6 on $FORGE
  g. emit markdown to stdout, appending <!-- themes-metadata --> when §1
     has commits
```

## Error Handling

| Condition | Behavior |
|---|---|
| Not in a git work tree | Print a one-line error to stderr, exit 1 |
| `git fetch` fails (offline) | Print `> note:` warning, continue against stale refs |
| `FORGE = github`, `gh` missing | Multi-line install hint (brew/apt/dnf + `gh auth login`), git-only sections |
| `FORGE = github`, `gh` installed but unauthed for hostname | Hint pointing at `gh auth login --hostname <h>`, git-only sections |
| `FORGE = gitlab`, `glab` missing | Multi-line install hint (brew/apt/dnf + `glab auth login`), git-only sections |
| `FORGE = gitlab`, `glab` installed but unauthed for hostname | Hint pointing at `glab auth login --hostname <h>`, git-only sections |
| `FORGE = unknown` | Silent — git-only sections, no forge-specific hint |
| Window start cannot be resolved and `DEFAULT_SINCE` is invalid | `> note:` warning, fall back to `7 days ago` literal |
| `jq` missing, `FORGE ∈ {github, gitlab}` with CLI present | Exit 1 with install hint (stderr) |
| `jq` missing, `FORGE = unknown` | `> note:` warning, skip forge-dependent sections |

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

1. **`promin/funnels-builder`** — GitLab, author is the user, multiple
   collaborators. Expected: all six sections populated, `!` prefix.
2. **An active GitHub repo** (e.g., a shallow clone of `cli/cli`). Expected:
   all six sections populated, `#` prefix, §6 shows workflow name.
3. **An unknown-forge repo** (e.g., `origin` pointing at Codeberg or a made-
   up host). Expected: git-only sections, no install hint.
4. **A GitHub repo with `gh` unavailable** (temporarily remove it from
   PATH). Expected: multi-line install hint + git-only sections.
5. **Empty window** — run immediately after a run with no new activity.
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
