## Context

Since v0.3.0 the whats-new skill emits a six-section markdown report.
Section §1 ("Merged to \<default-branch\> (N)") lists commit subjects — a
flat scroll of `feat: …` / `fix: …` lines. On active repositories that
degrades quickly: 30 commits spanning telemetry, security hardening, and
dependency bumps all land side-by-side. The user has to reconstruct the
story manually.

Reading commit diffs closes the gap, but unconditional diff
summarization is expensive — every invocation eats subscription tokens
(or API dollars), and the main session's context window fills up with
raw patch text the user never sees.

Current invariants that constrain the solution:

- **Script stays pure.** `skills/whats-new/scripts/whats-new.sh` is
  read-only against the repo (just `git fetch`, `git log`, `gh`, `glab`)
  and must not call any LLM directly. `claude -p` and similar approaches
  are out.
- **Skill step 2 is already LLM-authored.** The skill instructs Claude
  to "prepend a TL;DR" — that's the natural home for themes generation.
- **Token budget matters.** Repo-pulse runs frequently; a feature that
  always triples a session's token usage will be abandoned.

The user approved a threshold-based approach during brainstorming
(captured in `proposal.md`). This document resolves the remaining
implementation choices.

## Goals / Non-Goals

**Goals:**

- Surface *what work was done* (themes) — not just what was touched
  (commit subjects) — in §1 of the whats-new output.
- Keep the script's read-only / LLM-free posture intact.
- Scale gracefully: cheap on quiet repos, bounded on active ones.
- Let the user turn the feature off or force it on via userConfig.
- Protect the main session's context: raw diffs should not pollute
  Claude Code's conversation history when volume is high.

**Non-Goals:**

- Summarizing §3 open PRs, §4 my-activity, §5 awaiting-review, §6 CI.
- Themes for PR-only activity (merged PRs without a commit on the
  default branch).
- Cross-run caching. Every invocation recomputes.
- LLM calls from the bash script. No `claude -p` subprocess.
- A "regenerate themes" interactive command. Users rerun the skill.

## Decisions

### D1. Where summarization runs: skill step 2, not the script

Alternatives considered:

1. **Script calls `claude -p` per commit** — rejected: breaks read-only
   posture, adds network dependency, per-commit latency, needs
   auth mode handling.
2. **Skill step 2 reads diffs and summarizes in the host session** —
   chosen. Zero new dependencies; reuses the Claude Code session that
   already runs the skill; users already pay for this via their
   subscription or API key; simplest implementation.
3. **New separate Claude Code "summarizer" subagent only** — overkill
   for low-volume cases; always spawning a subagent wastes tokens on
   small repos.

### D2. Threshold-based dispatch with three modes

Alternatives considered:

1. **Always summarize every commit** — rejected: explodes on active
   repos; main-session context ballooning.
2. **Never summarize; enrich with shortstat only** — rejected: doesn't
   deliver semantic themes the user asked for.
3. **Threshold** — chosen. After filtering noise, measure two signals:
   `N` = eligible commit count, `DIFF_KB` = approximate patch size
   (from shortstat, not from reading diffs). Map to three modes:

   | Mode | Condition | Behavior |
   |------|-----------|----------|
   | `skip` | `N == 0` | No themes section at all |
   | `serial` | `N ≤ 10` AND `DIFF_KB ≤ 50` | Skill reads `git show <sha>` in main session; one pass; main session context includes diffs |
   | `parallel` | otherwise | Spawn one subagent per cluster (up to 8 concurrent); each subagent reads its own diffs and returns one sentence; main session sees only summaries |

   Numbers are starting defaults, not sacred. They live as constants at
   the top of SKILL.md §Implementation so a future PR can tune them.

### D3. Clustering before summarization

A naive "one theme per commit" output produces noise on big merges.
Cluster by `(author, conventional-commit-type, top-level-path)` tuple:

- **Author** — williammartin vs SamMorrowDrums group separately even if
  they touched the same area.
- **Type** — `feat:` and `fix:` from the same author on the same area
  still get different clusters (often tell different stories).
- **Top-level path** — `pkg/cmd/telemetry/*` and `pkg/cmd/auth/*` split
  into different clusters even for the same author + type.

If a cluster has only one commit after clustering, the commit subject +
shortstat carries it — no separate summary call.

### D4. Subagent dispatch rules (parallel mode)

When `parallel` mode triggers, the skill MUST:

1. Build the cluster list (post-filtering, post-grouping).
2. Cap concurrent subagents at **8**. If there are more clusters, run
   them in batches of 8 with the `Task` tool.
3. Each subagent receives:
   - A fixed prompt template: "Here are N commits by `<author>` with
     `<type>:` prefix, all touching `<path-root>`. Run `git show
     <sha>` for each and summarize in one sentence what they
     collectively accomplish. Reply with exactly one sentence, no
     preamble, no markdown formatting."
   - Its scoped tools: `Bash(git:*)` only. Not `gh`, not `glab`, not
     `Read` (the commit hashes + `git show` are enough).
   - An explicit context cap: "Do not read more than 30 lines of each
     diff; truncate large file blocks. Aim for the top-level change, not
     line-by-line."
4. Collect summaries; discard subagent runs that error out or time out
   — their cluster's commit subjects already appear in §1's list.

### D5. Filtering rules (pre-summarization)

Exclude from themes analysis:

| Criterion | Rule |
|-----------|------|
| Bot authors | Author name ends with `[bot]` (case-sensitive) — covers GitHub's convention (`dependabot[bot]`, `renovate[bot]`, `github-actions[bot]`) |
| Lock/vendor files only | Every file in the commit matches `*.lock` \| `go.sum` \| `package-lock.json` \| `yarn.lock` \| `Cargo.lock` \| `vendor/**` \| `node_modules/**` |
| Trivial dep bumps | Commit subject matches `^chore(\(deps\))?: bump ` AND shortstat additions ≤ 5 lines |
| Pure merge commits | Commit has ≥ 2 parents AND `git diff --name-only <parent1>..<parent2>` is empty |
| Docs-only changes | Every file matches `*.md` \| `docs/**` \| `README*` \| `LICENSE*` — these show up under §1 but rarely carry a "theme" |

Filtered commits are **not** removed from the existing §1 commit list —
they still appear as commit subjects. They are only excluded from
theme-generation input.

### D6. Output format — one sentence per theme

Themes section sits above §1:

```
## Themes this period
- **Telemetry rollout** (8 commits, williammartin): added `telemetry`
  command, error recording, host categorization, enabled without env var
- **Skill discovery fixes** (5 commits, SamMorrowDrums): nested `skills/`
  dirs supported, install-name matching, publish --fix correctness
- **Security hardening** (2 commits, williammartin + orbisai0security):
  log terminal injection fix, yaml shell-injection fix

## Merged to `trunk` (22)
- 2026-04-23 `aba7c59` ...
```

Rules:
- 3–6 bullets maximum. If the threshold produced more clusters, pick
  the top-six by commit count and drop the tail.
- Exactly one sentence per bullet; no sub-bullets; no emoji.
- Bold headline generated by the summarizer; parenthetical
  `(N commits, author1 + author2)` is mechanical from cluster metadata.

### D7. Script changes — emit shortstat alongside commits

Minimum script change: §1 today emits `date`, `sha`, `subject`,
`author`. Extend to also emit shortstat-derived fields as a
machine-readable block the skill can parse. Two options:

1. **Inline suffix** — append `[+A/-D N-files]` after each commit line.
   Human-readable; trivially greppable by the skill.
2. **Separate metadata block** — append `<!-- themes-metadata: ... -->`
   HTML comment at the end with one line per commit. Invisible in
   rendered markdown.

**Chosen: option 2 (separate block).** Keeps the visible §1 output
byte-identical to today's for users who run the raw script without the
skill; themes metadata is opt-in via parse. Skill step 2 parses the
HTML comment; on old script versions without the comment the skill
falls back to `git log --shortstat` on its own (one extra git call — ok).

### D8. Config: `summary_mode` and `summary_max_commits`

Two new userConfig keys in `.claude-plugin/plugin.json`:

- `summary_mode`: enum `auto` (default) | `off` | `always`
  - `auto` = threshold logic from D2
  - `off` = skip section entirely, output unchanged
  - `always` = force `parallel` path even when `serial` would qualify
- `summary_max_commits`: int, default **50**. Hard safety cap —
  if `N` (eligible commits post-filter) > this value, the skill
  degrades to `skip` and adds a note: `> note: too many commits this
  period (<N>); themes skipped. Narrow the window with --since.`

Rationale for cap: a three-month window on a busy repo can yield 500+
commits; users don't want 60+ subagents spinning up. The cap
protects against a mis-typed `--since`.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Subscription users hit rate limits unexpectedly | `summary_mode: auto` defaults. `summary_max_commits: 50` hard cap. Users can set `off` if concerned. Document token expectations in README. |
| Subagents disagree / produce inconsistent tone | Single prompt template (D4), explicit "one sentence, no preamble" constraint, single-model default (whatever the host session uses). |
| Subagent failure silently drops a theme | Clusters that fail return zero bullets; user still sees commit subjects in §1 unchanged. Log a `> note:` when a non-trivial fraction of clusters failed. |
| Clustering miscategorizes cross-cutting commits | Acceptable — worst case is a slightly awkward theme title. Themes are advisory; the commit list is authoritative. |
| Heuristic filters (bot detection, trivial-bump rule) miss edge cases | Filtered set only changes *themes* input; filtered commits still show in §1. False negative = one extra theme bullet; false positive = one less theme bullet. Non-critical either way. |
| Main-session context bloat in `serial` mode | Threshold `N ≤ 10` && `DIFF_KB ≤ 50` keeps raw diff content under ~50 KB in worst case; acceptable. Users with sensitivity can set `always` to force parallel (context stays clean). |
| Script output not byte-identical when metadata block added | Metadata is wrapped in `<!-- ... -->` — invisible in rendered markdown. Raw-text consumers see an extra trailing comment block but no change to section contents. |
| Version-skew between script and skill | Skill parses metadata defensively; if missing, falls back to `git log --shortstat`. One-directional compat: new skill + old script works; new script + old skill ignores the comment. |

## Migration Plan

Additive change — no migration needed for existing installs. After
`/plugin update repo-pulse@repo-pulse`:

1. Users with `summary_mode` unset see `auto` behavior immediately on
   repos with N>0 eligible commits.
2. Users who prefer the old behavior set `summary_mode: off` via the
   plugin config UI or `~/.claude/settings.json`.

Rollback: `summary_mode: off` is effectively a feature flag that
reverts to pre-0.4.0 output. No data migration required.

## Open Questions

None at spec time — all five brainstorming decisions were confirmed by
the user (threshold numbers, `auto` default, 8-subagent cap, one
sentence per bullet, separate OpenSpec change). Any future tuning of
thresholds or cluster rules is a follow-up change, not part of this
one.
