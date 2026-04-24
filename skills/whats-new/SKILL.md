---
name: whats-new
description: Summarize what changed in the current git repository since the user was last active. Produces a short prose narrative — what shipped, what's in flight (with collision heads-up if others are working near your WIP), what needs your attention, and what you did — with clickable PR and branch links. Use when the user asks "what's new", "catch me up", "what did the team do", or returns to a repo after an absence.
argument-hint: [--since=<period>]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/whats-new/scripts/whats-new.sh:*), Bash(git:*), Bash(glab:*), Bash(gh:*), Task
---

# whats-new

Run the summary script, then compose 1–4 prose paragraphs that describe
what happened in the repo and what needs the user's attention. The
script's structured markdown is **internal scratch** — never shown to
the user.

## Steps

1. Run the summary script. Pass through any `--since=<period>` argument
   the user provided; if they did not, run it with no arguments so the
   smart default resolves the window from the user's most recent commit
   (committer date) in this repo.

   ```
   ${CLAUDE_PLUGIN_ROOT}/skills/whats-new/scripts/whats-new.sh [--since=<period>]
   ```

2. Run the narrative pipeline defined in [§Narrative pipeline](#narrative-pipeline)
   below. Emit only the composed prose (plus the header) to the user.

3. Answer follow-up questions conversationally. `Bash(git:*)`,
   `Bash(glab:*)`, and `Bash(gh:*)` are in `allowed-tools` for this
   step — use them directly for things like "show me the diff for
   that branch", "what's in MR !1234" (GitLab), or "what's in PR
   #456" (GitHub) rather than re-running the summary script.

## Narrative pipeline

Zero LLM calls from the bash script. All composition happens in the
host Claude Code session.

### Empty-window short-circuit

If the script's output is the single line `Nothing new since <ISO>`,
emit that line verbatim and stop. Do not compose paragraphs, do not
emit the header.

### Constants

```
SERIAL_N_CAP          = 10    # max eligible commits for serial-mode reads
SERIAL_DIFF_KB_CAP    = 50    # max approximate diff KB for serial-mode reads
PARALLEL_CONCURRENCY  = 8     # max concurrent Task subagents in parallel mode
DEGRADED_FAILURE_PCT  = 25    # emit degraded note when this fraction of
                              # subagents failed in parallel mode
```

Retune only via a new OpenSpec change.

### Pipeline stages

```
script output (raw markdown + <!-- themes-metadata --> block)
    ↓
[A] Fact extraction — parse §1/§2/§3/§4/§5/§6 into fact buckets
    ↓
[B] URL base derivation — git remote get-url origin → host/owner/repo
    ↓
[C] Diff reads for Shipped paragraph — reuse 0.4.0 threshold engine
    (skip / serial / parallel) for §1 commits and §3 merged PRs
    ↓
[D] Collision detection — compare MY_BRANCHES vs THEIRS_BRANCHES
    ↓
[E] Paragraph composition — Shipped / In flight / Needs you / You
    ↓
[F] Link rendering — wrap PR, branch, commit refs in markdown links
    ↓
Output: header + paragraphs
```

### [A] Fact extraction

Parse the script's markdown output section-by-section into these
fact buckets. Headings are authoritative — if a section is missing,
its bucket is empty.

| Bucket | Source heading(s) | Per-entry fields |
|--------|-------------------|------------------|
| `shipped_commits` | `## Merged to \`<branch>\` (N)` | date, sha, subject, author |
| `shipped_prs` | `### Merged this period (N)` under `## Merge requests` | number/iid, title, author, source_branch, target_branch, status |
| `branches_new` | `## New / updated branches (N)` | branch, last_push_date, author, commits_ahead |
| `prs_open_others` | `### Open — others (N)` under `## Merge requests` | number/iid, title, author, source_branch, target_branch, status |
| `prs_open_mine` | `### Open — mine (N)` under `## Merge requests` | number/iid, title, author, source_branch, target_branch, status |
| `my_activity` | `## My activity (N commits across M branches)` | branch, commits[] (date, time, sha, subject) |
| `reviews_awaiting_me` | `## MRs awaiting my review (N)` OR `## PRs awaiting my review (N)` | number/iid, title, author, age_days |
| `ci_default` | `## CI on \`<branch>\`` | workflow_name (GitHub only), id, status, datetime, url |
| `themes_metadata` | HTML comment `<!-- themes-metadata … -->` | sha, author_name, added, deleted, files |
| `notes` | Lines starting with `> note:` anywhere in the output | raw text |

After extraction, strip the `<!-- themes-metadata -->` block so it
does not appear in the user-facing output.

### [B] URL base derivation

```
origin = $(git remote get-url origin)

# Normalize SSH and HTTPS:
#   git@github.com:cli/cli.git      → github.com, cli, cli
#   https://github.com/cli/cli.git  → github.com, cli, cli
#   https://gitlab.com/owner/repo.git → gitlab.com, owner, repo

host, owner, repo = parse(origin)  # strip .git suffix
```

Detect the forge from `host`: `github.com` or `ghe.*` → GitHub;
`gitlab.com` or any host where `glab auth status --hostname <host>`
reports "Logged in" → GitLab; else unknown.

On unknown forge, skip link wrapping — emit plain text (`#N`,
`` `branch` ``).

### [C] Diff reads for the Shipped paragraph

Reuse the 0.4.0 threshold engine:

1. Compute `N` = eligible `shipped_commits` after filtering
   (bots, lock/vendor-only, trivial dep bumps, pure merge commits,
   docs-only).
2. Compute `DIFF_KB` = Σ(added lines from themes_metadata) / 20.
3. Honor `summary_mode`:
   - `off` → skip diff reads; Shipped paragraph composed from
     subjects and titles only (degraded mode).
   - `always` → force parallel.
   - `auto` (default) → serial if `N ≤ SERIAL_N_CAP` AND `DIFF_KB ≤
     SERIAL_DIFF_KB_CAP`, else parallel; skip entirely if `N == 0`
     OR `N > summary_max_commits`.
4. Cluster eligible commits by `(author, conventional-commit-type,
   top-level-path)`. Single-commit clusters are fine.

**Serial mode:** for each cluster, `git show <sha>` each commit in
the host session; produce a one-or-two-sentence clause describing
what the cluster accomplished.

**Parallel mode:** dispatch one `Task` subagent per cluster, up to
`PARALLEL_CONCURRENCY` concurrent. Subagent prompt (replace fields):

```
You are summarizing a cluster of related git commits for a whats-new
report. Focus on what the commits collectively accomplished, not how.

Cluster metadata:
- author: <author>
- conventional-commit-type: <type>
- top-level path: <path-root>
- commits: <sha1>, <sha2>, ...

For each commit above, run `git show <sha>` and read the change.
Do not read more than 30 lines of any single file block; truncate
large file blocks. Skip past generated/lock files in your reading
order.

Reply with exactly one or two sentences of prose, suitable as a
clause inside a longer paragraph. No preamble. No markdown
formatting. No bullets. No emoji. Focus on the concrete change, not
generic context.
```

Subagent configuration:
- **subagent_type**: `general-purpose`
- **allowed tools**: `Bash(git:*)` only
- **model**: taken from `summary_model` (`haiku`, `sonnet`, `opus`).
  When `summary_model` is `inherit`, omit the `model` field so the
  subagent follows the host session.

Collect clauses. If ≥ `DEGRADED_FAILURE_PCT`% of subagents failed,
prepend a `> note: themes partially degraded: <k> of <n> clusters
failed to summarize` line above the narrative output (below the
header).

Failed clusters contribute to the Shipped paragraph at title-level
only, never as invented content.

#### Input filtering

Skip commits matching ANY of these before clustering:

- **Bot authors**: `author_name` ends with `[bot]` (case-sensitive).
- **Lock/vendor-only**: every file in the commit matches `*.lock`,
  `go.sum`, `package-lock.json`, `yarn.lock`, `Cargo.lock`,
  `vendor/**`, or `node_modules/**`. Determine file list via `git
  show --name-only --format='' <sha>`.
- **Trivial dep bumps**: subject matches `^chore(\(deps\))?: bump `
  AND shortstat additions ≤ 5.
- **Pure merge commits**: ≥ 2 parents AND empty cross-parent diff.
- **Docs-only**: every file matches `*.md`, `docs/**`, `README*`,
  or `LICENSE*`.

Filtered commits are not dropped from `shipped_commits` — they
still contribute to the Shipped paragraph at subject-level, they
are just excluded from cluster-and-summarize analysis.

### [D] Collision detection

Build the two sets before composing the In flight paragraph.

```
MY_BRANCHES = set(
    my_activity[*].branch                                  # §4
  ∪ output of `git branch --list --format='%(refname:short)'`
  ∪ current HEAD branch
)

THEIRS_BRANCHES = set(
    prs_open_others[*].source_branch                        # §3 Open — others
  ∪ branches_new[*].branch                                  # §2
)
```

Normalize both sets by lowercasing. Then for each `(mine, theirs)`
pair check:

1. **Name overlap**: `theirs` contains ≥ 3 consecutive characters
   of `mine` (or vice versa), AND the shared substring is not a
   common word in the exclusion set `{main, master, develop, dev,
   trunk, fix, feat, feature, chore, docs, test, wip}`.
2. **Path overlap**: the user's most recent commit on `mine` (via
   `git log -1 --name-only --format='' <mine>`) touches a
   top-level path `P`, AND an open PR whose source branch is
   `theirs` has `P` as a prefix of any file in its changed-files
   list, AND both the user's commit subject and the PR title start
   with the same conventional-commit type (`feat:`/`fix:`/etc.).

Matches go into the In flight paragraph as a heads-up phrase:

> Heads-up: <author>'s open <PR-link> touches the same
> `<path-root>` area as your branch <branch-link>.

If no collisions trigger, the In flight paragraph describes others'
work in neutral prose without a heads-up phrase.

### [E] Paragraph composition

Role order is fixed: **Shipped → In flight → Needs you → You**.
Paragraphs with no source data are omitted entirely.

#### Shipped paragraph

Stitches subagent clauses (or degraded-mode titles) into flowing
prose. Mentions:

- Main themes of merged work — typically 2–4 threads.
- Authors who drove them.
- Concrete PR or commit references for the user to follow up.

Shape guidance (not rigid):

> Over the past <window>, the team landed <thread 1> (<author>;
> <PR/commit refs>), <thread 2> (<author>; refs), and <thread 3>.
> [Optional: one sentence on a standout commit or security fix.]

Never write counts like "22 commits" — the user said numbers don't
matter. Focus on what happened.

#### In flight paragraph

Describes open PRs and new branches. Always includes the collision
heads-up phrase if collisions triggered in stage [D].

Shape guidance:

> In flight: <author1> has <PR-link> continuing <theme>;
> <author2> opened <branch-link> working on <theme>.
> Heads-up: <author3>'s open <PR-link> touches the same
> `<path>` area as your branch <branch-link>.

If there are many open PRs (10+), pick the 3–5 most notable (by
recency, by touch-area, by collision status) and summarize the rest
as "and a handful of dependency bumps / docs updates / …".

#### Needs you paragraph

Combines:

- `reviews_awaiting_me` → PRs you need to review (especially stale
  ones — age > 3 days).
- `ci_default` with status `failure` or `startup_failure`.
- `prs_open_mine` with failing checks.

Shape guidance:

> Two PRs await your review: <PR-link> (<author>, <age> days,
> stale) and <PR-link> (<author>, <age> days). CI on
> `<default-branch>` is red — the latest <workflow-name> run
> failed at <datetime>.

If none of the three inputs has content, omit this paragraph.

#### You paragraph

Describes the user's own recent activity from `my_activity`. Keep
it short — the user knows what they did; this is context, not
news.

Shape guidance:

> You pushed <N-ish, described in prose> commits yourself on
> <branch-link>: <brief description of the arc — new feature,
> cleanup, version bump, etc.>.

When `my_activity` covers multiple branches, mention each briefly.

### [F] Link rendering

Wrap references in markdown links using the URL base from [B]:

| Reference | GitHub template | GitLab template |
|-----------|------------------|------------------|
| PR/MR | `[#<N>](https://<host>/<owner>/<repo>/pull/<N>)` | `[!<iid>](https://<host>/<owner>/<repo>/-/merge_requests/<iid>)` |
| Branch | `` [`<branch>`](https://<host>/<owner>/<repo>/tree/<branch>) `` | `` [`<branch>`](https://<host>/<owner>/<repo>/-/tree/<branch>) `` |
| Commit | `` [`<sha>`](https://<host>/<owner>/<repo>/commit/<sha>) `` | `` [`<sha>`](https://<host>/<owner>/<repo>/-/commit/<sha>) `` |

On unknown forge, emit plain text instead: `#<N>`, `` `<branch>` ``,
`` `<sha>` ``. No empty link wrappers, no fallback URLs.

Claude Code's terminal renderer handles markdown links natively —
no OSC 8 escape sequences are emitted.

### Final output

```
# What's new in <repo-slug>

Window: <ISO start> → <ISO end> (<reason>)

<optional > note: lines from the script or the pipeline>

<Shipped paragraph, if present>

<In flight paragraph, if present>

<Needs you paragraph, if present>

<You paragraph, if present>
```

Paragraphs are separated by a blank line. Omit the `<!-- themes-metadata -->`
block and any `##`-level headings from the script's scratch output
— the user never sees them.

## Notes

- The script is read-only against the repository (it runs `git fetch`,
  nothing else mutates state).
- The script auto-detects the forge (GitHub, GitLab, or unknown) from
  the origin URL, falling back to `gh`/`glab auth status --hostname <h>`
  probes for GitHub Enterprise and self-hosted GitLab.
- If `> note: origin is on GitHub/GitLab but …` appears, surface the
  install hint the script already emitted; the user just needs to run
  the shown `brew install gh` (or apt/dnf equivalent) and `gh auth
  login` / `glab auth login` — and rerun. Don't re-type the hint, the
  script already did.
- If `> note: no git user.email set and extra_emails is empty …`
  appears, tell the user either to set `git config user.email` in this
  repo or to add addresses to the `extra_emails` userConfig value (via
  Claude Code's plugin-config UI, or by editing
  `~/.claude/settings.json` directly under
  `pluginConfigs."repo-pulse".options`).
- On unknown-forge origins (Gitea, Codeberg, etc.) the script produces
  only sections 1, 2, and 4 — this is by design, not a bug. The
  narrative still renders (In flight paragraph may be shorter).
- `summary_mode: off` is the escape hatch for users who want to save
  tokens: Shipped paragraph degrades to commit-subject prose, other
  paragraphs render normally.
- Users who want the old six-section structured output can run the
  script directly: `${CLAUDE_PLUGIN_ROOT}/skills/whats-new/scripts/whats-new.sh`.
  The structured view is still produced — it's just the skill's
  internal scratch, not the user-visible output.
