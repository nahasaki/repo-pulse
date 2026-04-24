## Why

The six-section markdown report we've shipped through 0.5.0 is
comprehensive but dense — on active repositories a single
invocation can produce 60-80 lines across merged commits, branches,
open PRs, merged PRs, PRs awaiting review, and CI. A user returning
to a repo does not want a catalog; they want to understand three
things in roughly this order:

1. What shipped while I was away (and who did it)?
2. Who's already working on what — am I about to duplicate someone's
   effort on my current branch?
3. Does anything need my attention right now (reviews, failing CI)?

The existing Themes section (added in 0.4.0) already moves in that
direction for §1, but it's layered on top of the old structured
output. This change replaces the structured sections entirely with
1–4 paragraphs of prose answering exactly those three questions,
plus an optional "what you did" paragraph when the user has their
own activity worth mentioning. The script stays read-only and
unchanged; all transformation happens in the skill.

## What Changes

- **BREAKING** (for humans skimming the output — not for any
  machine consumer, since there are none): replace the six
  structured sections (`## Merged to …`, `## New / updated
  branches`, `## Merge requests`, `## My activity`, `## MRs awaiting
  my review`, `## CI on …`) with a **Narrative overview** composed
  of prose paragraphs. The header line and `Window:` line remain.
- Extend the skill pipeline to **extract facts from the script's
  markdown output** (which still uses the current section format —
  it becomes an internal data source rather than user-facing
  output).
- Add a **collision detection** step: cross-reference open-PR source
  branches and newly updated remote branches with the user's local
  branches and §4 "my activity" branches. When name similarity or
  topical overlap is detected, call it out explicitly in the
  "in flight" paragraph so the user sees "someone else is working on
  your thing" before they spend a day duplicating it.
- Render **PR and branch references as markdown links**
  (`[#1234](https://github.com/owner/repo/pull/1234)`) so they're
  clickable in Claude Code's terminal renderer. The skill builds
  URLs from the origin and the forge-specific path convention.
- Retire the existing `## Themes this period` section, the `## TL;DR`
  step-2 prepend, and the six structured sections. Their content
  gets absorbed into the narrative paragraphs.
- Keep `summary_mode` and `summary_max_commits` semantics intact:
  `summary_mode: off` now means "produce a minimal prose output
  based on counts and titles only, skip diff reads". `summary_mode:
  always` still forces parallel subagents. `summary_max_commits`
  still caps diff-read input.
- Keep `summary_model` intact: still controls the model used by
  parallel-mode diff-reading subagents.
- Bump plugin version to **0.6.0** (user-facing output format
  change; existing config keys retain semantics).

## Capabilities

### New Capabilities
<!-- None. This change modifies the existing whats-new capability. -->

### Modified Capabilities
- `whats-new`: the main output-format requirement changes from
  "six-section markdown output" to "narrative prose output" with
  paragraph roles (Shipped / In flight / Needs you / You). The
  themes requirement is replaced. New requirements are added for
  collision detection, PR/branch linkification, and the fact-
  extraction layer between the script and the renderer.

## Impact

- `skills/whats-new/SKILL.md` — step 2 completely rewritten. The
  existing §Themes pipeline mutates into a §Narrative pipeline with
  a fact-extraction phase, a collision-detection phase, and a
  paragraph composition phase.
- `skills/whats-new/scripts/whats-new.sh` — no logic changes. The
  script continues to emit the structured markdown it always has;
  that markdown is now consumed internally by the skill and never
  shown to the user. The `themes-metadata` HTML-comment block also
  remains and feeds the threshold decision.
- `SPEC.md` — §Output Format completely rewritten. §Themes filtering
  and threshold dispatcher sections remain (they still drive diff
  reads inside the new pipeline). New subsections on paragraph
  roles, collision detection, and link formatting.
- `README.md` — update the Example section intro (if we reintroduce
  one) and the Features list to reflect prose-first output. No
  Configuration-table changes.
- `openspec/specs/whats-new/spec.md` — synced at archive time with
  MODIFIED/ADDED/REMOVED requirements from this delta.
- No new `userConfig` keys. Existing `summary_mode`,
  `summary_max_commits`, `summary_model` retain their roles.

## Non-goals

- No output-format switcher (e.g., `output_format: structured | narrative`).
  The user explicitly rejected this as unnecessary complexity. The
  new default is the only format; users who want the old six-section
  view can pin plugin version 0.5.0.
- No cross-run memory of what was previously shown. Each invocation
  is stateless.
- No automatic PR-diff reading. Open-PR metadata (title, source
  branch, changed-files list) from the existing `gh`/`glab` payloads
  suffices for the "in flight" paragraph. Reading diffs of N open
  PRs would blow the token budget.
- No user-linking (`@username`). PR and branch links are sufficient.
- No numeric aggregates in prose (e.g., "22 commits, 5 branches, 23
  PRs"). Exact counts are the kind of detail the user said did not
  matter.
- No changes to §1's commit-collection behavior in the script.
  Themes-metadata block format is unchanged — it still drives the
  threshold decision.
- No new gotchas about OSC 8 terminal escapes: Claude Code's
  renderer handles markdown links natively, so we emit standard
  markdown `[text](url)` and let the client render it. No raw
  escape sequences.
