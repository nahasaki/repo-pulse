---
name: whats-new
description: Summarize what changed in the current git repository since the user was last active. Shows merged commits on the default branch, new or updated remote branches, open and merged MRs on GitLab, the user's own recent commits, MRs awaiting review, and CI status on the default branch. Use when the user asks "what's new", "catch me up", "what did the team do", or returns to a repo after an absence.
argument-hint: [--since=<period>]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/whats-new/scripts/whats-new.sh:*), Bash(git:*), Bash(glab:*), Bash(gh:*), Task
---

# whats-new

Summarize activity in the current git repository, then add a short
TL;DR and — on active repositories — a "## Themes this period" section
derived from commit diffs before emitting the script's markdown.

## Steps

1. Run the summary script. Pass through any `--since=<period>` argument the
   user provided; if they did not, run it with no arguments so the smart
   default resolves the window from the user's most recent commit (committer
   date) in this repo.

   ```
   ${CLAUDE_PLUGIN_ROOT}/skills/whats-new/scripts/whats-new.sh [--since=<period>]
   ```

2. Build the themes section and the TL;DR, then emit the composed markdown
   to the user. See [§Themes pipeline](#themes-pipeline) below for the full
   filter → cluster → threshold → summarize flow. The final output order is:

   1. TL;DR (1–3 bullets, always)
   2. `## Themes this period` (3–6 bullets, when the threshold engine produced any)
   3. The script's markdown, unchanged, minus the trailing `<!-- themes-metadata -->` block

   The TL;DR surfaces whatever is most actionable:
   - Remote branches whose names look similar to the user's current WIP —
     they may have already pushed this work from another machine or a
     colleague is duplicating it.
   - Stale open MRs in "MRs awaiting my review" (high age).
   - Failing CI on the default branch.
   - Lines beginning with `> note:` — surface those; they explain
     degraded modes (offline, unknown-forge origin, missing CLI, missing
     identity, cap-exceeded themes, degraded themes, etc.).

   If nothing stands out, skip the TL;DR and let the sections speak for
   themselves.

3. Answer follow-up questions conversationally. `Bash(git:*)`,
   `Bash(glab:*)`, and `Bash(gh:*)` are in `allowed-tools` for this step —
   use them directly for things like "show me the diff for that branch",
   "what's in MR !1234" (GitLab), or "what's in PR #456" (GitHub) rather
   than re-running the summary script.

## Themes pipeline

This pipeline runs during step 2. It is entirely in-session — no LLM
calls from the bash script, `claude -p` is not used.

### Constants

```
SERIAL_N_CAP          = 10    # max eligible commits for serial-mode reads
SERIAL_DIFF_KB_CAP    = 50    # max approximate diff KB for serial-mode reads
PARALLEL_CONCURRENCY  = 8     # max concurrent Task subagents in parallel mode
OUTPUT_BULLET_CAP     = 6     # max themes bullets in the final section
DEGRADED_FAILURE_PCT  = 25    # emit degraded note when this fraction of
                              # subagents failed in parallel mode
```

Defaults — tune only with a follow-up OpenSpec change, not ad-hoc.

### Inputs

- **`themes-metadata` block** from the end of the script's output. CSV
  rows: `sha,author_name,added,deleted,files`. One row per §1 commit.
- **`CLAUDE_PLUGIN_OPTION_SUMMARY_MODE`** — `auto` (default) | `off` |
  `always`. Unknown values treated as `auto` with a `> note:`.
- **`CLAUDE_PLUGIN_OPTION_SUMMARY_MAX_COMMITS`** — integer, default 50.

If the metadata block is missing (older script version or §1 empty),
fall back to `git log --shortstat` with the same `--since` the script
used. If §1 is empty in the visible output, skip the pipeline — there
is nothing to theme.

### Filtering (before clustering)

Exclude these commits from themes analysis. They STAY in the §1
commit list — filtering only removes them from cluster-and-summarize
input.

| Criterion | Rule |
|-----------|------|
| Bot authors | `author_name` ends with `[bot]` (e.g., `dependabot[bot]`, `renovate[bot]`, `github-actions[bot]`) |
| Lock/vendor-only | Every file in the commit matches `*.lock`, `go.sum`, `package-lock.json`, `yarn.lock`, `Cargo.lock`, `vendor/**`, or `node_modules/**` |
| Trivial dep bumps | Subject matches `^chore(\(deps\))?: bump ` AND shortstat additions ≤ 5 |
| Pure merge commits | `git cat-file -p <sha>` shows ≥ 2 parents AND `git diff --name-only <parent1>..<parent2>` is empty |
| Docs-only | Every file matches `*.md`, `docs/**`, `README*`, or `LICENSE*` |

Decide lock/vendor-only and docs-only by running `git show --stat
--name-only --format='' <sha>` on candidate commits (the metadata
block gives sha + counts but not paths). Be conservative: if *any*
file in the commit sits outside the exclusion patterns, do NOT filter
the commit.

### Signals

After filtering, compute:

- `N` = count of eligible commits.
- `DIFF_KB` = Σ(added lines from metadata) / 20. (Rough proxy — 20
  lines ≈ 1 KB of patch content.)

### Dispatch

| Mode | Condition | Behavior |
|------|-----------|----------|
| `skip` | `N == 0`, OR `N > summary_max_commits`, OR `summary_mode == "off"` | No themes section. If skipped due to cap, prepend a note: `> note: too many commits this period (<N>); themes skipped. Narrow the window with --since.` |
| `serial` | `summary_mode == "auto"` AND `N ≤ SERIAL_N_CAP` AND `DIFF_KB ≤ SERIAL_DIFF_KB_CAP` | Read `git show <sha>` for each cluster's commits in the host session. Main session context includes raw diffs. |
| `parallel` | `summary_mode == "always"`, OR `auto` when `serial` conditions are not met | Dispatch one Task subagent per cluster, up to `PARALLEL_CONCURRENCY` concurrent. Subsequent clusters run in additional batches of 8. Main session sees only one-sentence summaries. |

### Clustering

Key per commit: `(author, conventional-commit-type, top-level-path)`.

- **author** — `author_name` from the metadata block.
- **conventional-commit-type** — prefix before `(` or `:` in the
  commit subject. Recognized: `feat`, `fix`, `refactor`, `chore`,
  `docs`, `test`, `perf`, `ci`, `build`, `style`. Anything else
  collapses to `other`.
- **top-level-path** — shallowest common ancestor directory of all
  files touched by the commit. Run `git show --name-only --format=''
  <sha>` to list files. If the commit touches unrelated top-levels
  (e.g., `pkg/foo/*` and `cmd/bar/*`), use the synthetic token
  `<mixed>`.

Merge single-commit clusters only when the commit subject is already
informative (a conventional commit with a clear message). Otherwise
summarize even single-commit clusters through the chosen mode.

### Serial mode

For each cluster in any order:

1. `git show <sha>` for each commit in the cluster. Keep in the
   current session's working memory.
2. Produce one sentence: "what these commits collectively
   accomplish". No preamble, no list, no emoji.
3. Record the bullet as `(cluster-metadata, sentence)`.

Truncate raw diff reading to ~30 lines per file block — enough for
intent, not for line-by-line analysis.

### Parallel mode

For each batch of up to `PARALLEL_CONCURRENCY` clusters:

Dispatch Task subagents in a single message with this shape:

- **subagent_type**: `general-purpose`
- **description**: e.g., `Summarize 8 telemetry commits`
- **prompt** (fixed template, replace fields):

  ```
  You are summarizing a cluster of related git commits for a whats-new
  report. Focus on what the commits collectively accomplish, not how.

  Cluster metadata:
  - author: <author>
  - conventional-commit-type: <type>
  - top-level path: <path-root>
  - commits: <sha1>, <sha2>, ...

  For each commit above, run `git show <sha>` and read the change.
  Do not read more than 30 lines of any single file block; truncate
  large file blocks. Skip past generated/lock files in your reading
  order.

  Reply with exactly one sentence. No preamble, no markdown
  formatting, no bullets, no emoji. Include the main feature or fix
  the cluster delivers.
  ```

Allowed tools for the subagent: `Bash(git:*)` only. Do not grant
`Bash(gh:*)`, `Bash(glab:*)`, `Read`, or `Write`.

Collect returns; if a subagent errors or times out, drop that cluster
silently. Track the failure rate across all clusters in this run.

### Graceful degradation

After parallel dispatch:

- If ≥ `DEGRADED_FAILURE_PCT`% of clusters failed (e.g., 2+ of 8), emit
  a `> note: themes partially degraded: <k> of <n> clusters failed to
  summarize` line just above the themes section.
- If every cluster failed, skip the themes section entirely and emit
  the note on its own line.

### Rendering the themes section

Assemble bullets from successful summaries:

```
## Themes this period
- **<theme title>** (<N> commits, <author1>[ + <author2> + others]): <one sentence>
```

Rules:

- 3–6 bullets max. If more clusters summarized, keep top-6 by commit
  count, drop the tail silently.
- Bold theme title from the summarizer; the parenthetical
  `(N commits, ...)` is mechanical from cluster metadata.
- Author list truncates to `author1 + author2 + others` when three or
  more distinct authors share a cluster.
- Exactly one sentence per bullet. No sub-bullets. No emoji.
- Strip the `<!-- themes-metadata -->` block from the final output
  sent to the user — it is an implementation detail.

### When the themes section is empty

If dispatch returned no bullets (skip mode, or all clusters failed),
do NOT emit `## Themes this period` at all. The rest of the script
output still renders normally.

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
  only sections 1, 2, and 4 — this is by design, not a bug. Themes
  still work because they rely on §1 only.
- `summary_mode: off` is the escape hatch for any user who sees the
  themes section as noise or who wants to preserve pre-0.4.0 token
  usage.
