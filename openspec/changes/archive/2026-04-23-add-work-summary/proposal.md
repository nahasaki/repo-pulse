## Why

Today's §1 "Merged to <default-branch>" section lists commit titles, which
is fine metadata but rarely conveys what work was actually done. A user
returning to a repository after a week wants to understand themes —
"telemetry rollout", "skill discovery fixes" — not scan 30 commit subjects
and reconstruct the story manually. Reading diffs solves this, but
summarizing every diff unconditionally is expensive (tokens on a
subscription, dollars on an API key). A threshold-based approach gives
meaningful summarization for free on small activity and scales gracefully
to large activity via parallel subagents — bounded by a configurable
budget and the existing `summary_mode` knob.

## What Changes

- Add a new `## Themes this period` section above §1 in the script's
  markdown output — populated by the skill (not the script) in
  `SKILL.md` step 2 after the shell script finishes.
- Extend the script to emit per-commit shortstat data (additions/deletions,
  touched paths) as machine-readable metadata so the skill can make
  budget decisions without re-running git.
- Introduce a three-mode threshold dispatcher in the skill: `skip` when no
  eligible commits remain after filtering; `serial` when volume is low;
  `parallel` (via the `Task` tool) when volume is high — default cap of
  eight concurrent subagents, one per cluster.
- Cluster eligible commits by author × conventional-commit type × top-level
  path before summarization to avoid per-commit fragmentation and to give
  each subagent a focused prompt.
- Filter noise before themes analysis: bot authors (`[bot]` suffix),
  lock/vendor paths (`*.lock`, `go.sum`, `vendor/**`, `node_modules/**`),
  trivial `chore(deps): bump …` bumps with small shortstat, and pure
  merge commits. Filtered commits remain in §1's commit list; they are
  only excluded from themes analysis.
- Add two new `userConfig` knobs to `.claude-plugin/plugin.json`:
  `summary_mode` (`auto` default, `off`, `always`) and
  `summary_max_commits` (int, default 50 — hard safety cap).
- Update SPEC.md §Output and §Configuration to document the new section,
  the thresholds, the filtering rules, and the new config keys.
- Bump plugin version to **0.4.0** (additive feature, not breaking).

## Capabilities

### New Capabilities
<!-- None. This change modifies the existing whats-new capability. -->

### Modified Capabilities
- `whats-new`: add requirements for the themes section, the threshold
  dispatcher, the filtering rules, and the new `summary_mode` /
  `summary_max_commits` userConfig values. Delta spec will live under
  `specs/whats-new/spec.md` of this change.

## Impact

- `skills/whats-new/scripts/whats-new.sh` — extend §1 commit collection
  to emit shortstat-enriched records for the skill to consume. No new
  network calls; all data from local git.
- `skills/whats-new/SKILL.md` — expand step 2 to implement the filter →
  cluster → threshold → summarize pipeline and prepend the themes
  section before emitting the markdown to the user.
- `.claude-plugin/plugin.json` — add `summary_mode` and
  `summary_max_commits` to `userConfig`; bump `version` to 0.4.0.
- `SPEC.md` — new subsections under §Output (themes section) and
  §Configuration (summary_mode, summary_max_commits).
- No impact on §2 branches, §4 my-activity, §5 awaiting-review, §6 CI —
  themes are §1-only. No changes to the script's read-only posture
  (still `git fetch` + `git log`/`gh`/`glab`, nothing else).

## Non-goals

- No LLM calls from the bash script. `claude -p` and similar subprocess
  approaches are explicitly out of scope — summarization is the skill's
  responsibility, via the host Claude Code session.
- No cross-run caching of summaries. Each invocation is fresh; simpler
  implementation, no stale cache concerns.
- No summarization for §3 open PRs, §4 my-activity, §5 awaiting-review,
  or §6 CI. PR titles are usually informative enough; the user already
  knows their own work; awaiting-review is status-critical; CI is just a
  state flag.
- No themes for PR-without-merge — only commits landed on the default
  branch qualify. PR titles in §3 already cover in-flight work.
- No user-facing "regenerate themes" command. If the user wants
  themes recomputed, they rerun `/repo-pulse:whats-new`.
