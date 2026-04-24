## Context

Through 0.5.0 the skill renders a six-section markdown report that
mirrors the shell script's output, with the Themes section (0.4.0)
prepended above §1 when the threshold engine has something to say.
The user's lived experience: on active repositories that output is
dense and hard to scan, even though every individual section is
clear. The user asked for a prose-first rewrite of the visible
output while keeping the script unchanged.

Constraints from the explore conversation:

- **No new userConfig.** Existing knobs (`summary_mode`,
  `summary_max_commits`, `summary_model`) must keep working.
- **Prose replaces structure.** No toggle, no fallback; the old
  format is gone.
- **Collision detection matters.** "Did someone start working on
  what I was planning?" is named as the most important signal
  besides "what shipped".
- **PR/branch references stay navigable** via markdown links
  rendered by Claude Code.
- **Commit messages lie sometimes** — so the pipeline must read
  diffs (commit messages AND `git show`) for the "shipped"
  paragraph, same as today's Themes pipeline.
- **Multi-paragraph output** is fine; empty paragraphs are
  skipped.

## Goals / Non-Goals

**Goals:**

- Replace the six-section report with 1–4 prose paragraphs of
  ordered roles: Shipped → In flight → Needs you → You.
- Surface branch/PR collisions between the user's WIP and others'
  active work prominently, not as an afterthought.
- Make PR and branch references clickable without introducing
  new terminal-escape handling.
- Reuse the existing diff-reading threshold infrastructure
  (serial vs parallel, `summary_model`, budget caps) — do not
  reimplement.

**Non-Goals:**

- An output-format switcher. One format, no knob.
- Reading diffs of open PRs (budget blow-up).
- User @mentions.
- Numeric totals in prose.
- Script-side changes beyond what's already shipped.

## Decisions

### D1. The script stays as-is; the skill treats its output as scratch

Alternatives considered:

1. **Rewrite the script to emit machine-readable JSON instead of
   markdown** — rejected. Large surface-area change, loses the
   human-runnable-from-terminal property of the script, and
   produces a second data format we'd have to maintain. The
   existing markdown is trivially re-parseable section-by-section
   with simple grep/awk.
2. **Skill parses the script's markdown to extract facts** —
   chosen. Minimal change to the script contract, which also
   preserves the escape hatch "run the script directly, get the
   old six sections" for anyone debugging. The skill becomes the
   view layer.
3. **Script emits both structured markdown AND a JSON sidecar** —
   rejected. Extra complexity, two sources of truth.

### D2. Paragraph roles, fixed order, skip-when-empty

Four roles:

| Role | Source sections | Show when |
|------|-----------------|-----------|
| **Shipped** | §1 Merged + §3 Merged this period | Any merged commits or merged PRs exist in-window |
| **In flight** | §2 New/updated branches + §3 Open (others) + collision flag | Any open PRs or new branches exist |
| **Needs you** | §5 Awaiting review + §6 CI failures + §3 Open (mine) with stalled checks | Any reviews waiting, CI red, or mine-PRs with failing checks |
| **You** | §4 My activity | User has commits in the window |

Order is fixed. Each role emits either zero paragraphs (skipped) or
one paragraph. A quiet repo with only user activity produces a single
"You" paragraph. A busy repo can produce all four.

Why fixed order: humans read top-down; "what shipped" is usually the
most interesting context, "in flight / collisions" is the next
priority (affects your plan), "needs you" is the actionable
attention-grabber, "you" is background info.

### D3. Collision detection — cheap string overlap, no semantic guessing

The skill compares:
- `MY_BRANCHES` = list from §4 "My activity" section + current
  checked-out branch + any in-progress refs (`git branch --list`).
- `THEIRS_BRANCHES` = source branches of open PRs (§3 Open — others)
  plus new remote branches (§2).

Collision triggers when:

1. **Name overlap**: an other-branch name shares ≥ 3 consecutive
   path segments or substrings with any of MY_BRANCHES after lowercasing
   (e.g., `user/my-auth-work` vs `user/my-auth-fixes` → trigger;
   `auth/fixes` vs `telemetry/add-command` → no trigger).
2. **Same conventional-commit prefix + overlapping top-level path**:
   if the user's most recent commit on their WIP branch touches
   `pkg/cmd/auth/` and an open PR's title begins with `feat(auth)` or
   its source branch is `feat-auth-…`, flag it.

Matches go into the "In flight" paragraph prefixed with **heads-up**:
> *Heads-up: Sam's open PR [#13266] for skill install pathing
> overlaps with work on your branch `sammorrowdrums/fix-…`.*

No heuristic is perfect; false positives are acceptable because the
user is the judge. False negatives are the failure mode — we'd rather
over-flag than miss a real collision. The skill still mentions non-
colliding work as context in the same paragraph.

Alternatives considered:

1. **Cheap string overlap** — chosen. Fast, no LLM call, explainable.
2. **Semantic similarity via embedding or model call** — rejected.
   Another token cost, another model dependency, and the collision
   question is crisp enough that string rules do most of the job.

### D4. PR/branch linkification — markdown only

Emit `[#1234](https://github.com/owner/repo/pull/1234)` or
`[!5678](https://gitlab.com/owner/repo/-/merge_requests/5678)`. Branch
references become `` [`branch-name`](url) ``.

URL construction:

- Forge: detected by the existing script logic, written into the
  header area of the script's output (not currently visible — we'll
  add a `<!-- forge: github -->` hint or just call `git remote
  get-url origin` from the skill).
- Owner/repo: parse from the origin URL.
- Path convention per forge:
  - GitHub: `/pull/<N>`, `/tree/<branch>`
  - GitLab: `/-/merge_requests/<iid>`, `/-/tree/<branch>`

On unknown-forge origins, emit plain text (`#1234`, `` `branch-name` ``)
without links — they still carry meaning even without URLs.

Claude Code renders standard markdown; no OSC 8 escape needed.

### D5. Composition: serial vs parallel reuse from 0.4.0

The existing threshold engine (`summary_mode`, N, DIFF_KB, subagent
dispatch, `summary_model`) continues to govern diff reads for the
"Shipped" paragraph. The pipeline split:

```
[script output + themes-metadata block + forge/origin]
                    ↓
            [FACT EXTRACTION]
                    ↓
        ┌───────────┴────────────┐
        ▼                        ▼
  [SHIPPED diffs]         [IN-FLIGHT metadata]
  (threshold logic        (no diff reads;
   reused from 0.4.0:     just title/source/files
   serial or parallel     from script output)
   based on N, DIFF_KB)
        ↓                        ↓
  [SHIPPED paragraph]      [COLLISION check →
                            IN FLIGHT paragraph]
                                 ↓
                          [NEEDS-YOU paragraph]
                                 ↓
                          [YOU paragraph]
                    ↓
                [COMPOSE + LINKIFY]
                    ↓
                 [OUTPUT]
```

The subagents that already exist (one per cluster of merged work)
now return input for the Shipped paragraph specifically, not a
standalone bullet in a Themes section. Prompt template is adjusted
(D6). The 25%-failure degradation rule still applies; if most
subagents fail, the Shipped paragraph degrades to "N things landed;
[#123] notable titles…" without the synthesized narrative.

### D6. Subagent prompt — composes a sentence or two, not a bullet

Current 0.5.0 prompt asks for "exactly one sentence, no preamble".
The new prompt asks for "one or two sentences describing what these
commits accomplished, suitable as a clause inside a longer paragraph".
The skill then stitches those clauses into a flowing Shipped
paragraph — not a bullet list.

Implication: prose quality depends on stitching. The compose step
must add connective tissue ("…, while …", "Separately, …"). That
stitching happens in the host session, not in subagents.

### D7. `summary_mode: off` degrades prose, doesn't suppress output

Today `off` means "no themes section at all; rest of output
unchanged". With prose as the only format, that becomes
"still produce the prose, but skip the expensive diff-read step —
use commit subjects and PR titles only". The "Shipped" paragraph
then reads:

> Five commits landed this period, mostly chore dependency bumps
> and one fix from William Martin (log terminal injection). Three
> open PRs continue telemetry work…

Quality drops (no semantic clustering, no theme titles) but prose
still renders. Users who truly want silence can set a long
`--since` that excludes everything, or just not run the skill.

### D8. Header retained

Header output before paragraph 1:

```
# What's new in <repo-slug>

Window: <start ISO> → <end ISO> (<reason>)
```

Same as today. Users need to know what repo + period they're looking
at. Two lines, no cost.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Collision detection fires false positives ("heads-up" about unrelated branches) | Heuristic is conservative — requires ≥ 3 consecutive shared substrings OR path-overlap anchor. Users can ignore false positives. False negatives are worse than false positives for this use case. |
| Prose hallucinates a fact not in the script output | Compose step receives all source facts as structured JSON-like input to the LLM; prompt explicitly says "do not invent, use only the provided facts". Stitching errors tolerated; fabrications must not happen. |
| Loss of exact counts and SHAs bothers power users | User accepted this tradeoff in the explore conversation. Power users can run the script directly (`${CLAUDE_PLUGIN_ROOT}/skills/whats-new/scripts/whats-new.sh`) to get the old structured output — it's read-only and still works. |
| Open-PR metadata misses critical detail (e.g., description body) | The "In flight" paragraph uses title + source branch + files-changed-count from the existing `gh/glab` payloads. Users with follow-up questions can ask "what's in PR #X" and Claude reads the body at that point. |
| Markdown links break on exotic terminals | On terminals without link support, `[text](url)` renders as the literal text `[text](url)`. Still readable, just ugly. Claude Code, iTerm, Terminal.app, Alacritty, Kitty all render them correctly. |
| Forge detection returns `unknown` → no URLs | Plain text fallback (`#1234`, `` `branch-name` ``). Information is still there; links are an optimization. |
| Pipeline complexity grows — harder to debug | Keep the script's structured output intact; anyone debugging can inspect what the skill saw by running the script directly. The skill's compose step is a single LLM call with a fixed template — auditable. |
| Stitching sentences from subagents produces awkward prose | Acceptable for an in-terminal summary. If it consistently reads badly we iterate the compose prompt; not a blocker. |
| Empty windows ("nothing new") lose their punchline | Preserve the existing "Nothing new since <ISO>" one-liner for the empty case — the skill detects this from the script's `Nothing new …` exit path and passes through. |

## Migration Plan

Additive in architecture (no knob removal, no data loss), but
user-visible output format changes. Steps:

1. Ship 0.6.0 to the marketplace.
2. Users on `/plugin update` see the new prose output next invocation.
3. Anyone who wants the old structured output: `git clone
   nahasaki/repo-pulse`, check out the `v0.5.0` tag, install via
   `--plugin-dir` — same as any other version rollback.

Rollback: none needed inside the plugin. It's a pure-skill change.

## Open Questions

- **Should we hyphenate "In-flight" in the paragraph output?** Styling
  only. Pick "In flight" (no hyphen) for consistency with natural
  English.
- **Should empty paragraphs emit a divider line `---` or just collapse
  silently?** Collapse silently. Less noise.
- **Do we want a subtle footer like `(run with --since=14d for a
  broader view)` when the window is short?** Out of scope for 0.6.0.
  Consider in a later polish pass.
