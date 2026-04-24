## 1. Plugin manifest

- [x] 1.1 Bump `version` in `.claude-plugin/plugin.json` from `0.5.0` to `0.6.0`
- [x] 1.2 Run `claude plugin validate .claude-plugin/plugin.json` and confirm it passes

## 2. Skill — step 2 rewrite (narrative pipeline)

- [x] 2.1 In `SKILL.md` step 2, replace the existing §Themes pipeline with a §Narrative pipeline. Keep the Constants block; retire the "prepend TL;DR + themes" output stitching. The new step 2 consumes the script's markdown as internal scratch and emits prose.
- [x] 2.2 Document the fact-extraction stage: how to parse §1, §2, §3 (three subsections), §4, §5, §6 and the `<!-- themes-metadata -->` block into per-role fact buckets
- [x] 2.3 Document URL construction: read `git remote get-url origin`, normalize HTTPS/SSH, strip `.git`, derive `<host>/<owner>/<repo>`; produce GitHub and GitLab link paths per the delta spec table
- [x] 2.4 Document collision detection: build `MY_BRANCHES` (from §4 + current checkout + `git branch --list`) and `THEIRS_BRANCHES` (from §2 + §3 Open — others); apply the name-overlap and path-overlap rules; flag matches with a "heads-up" phrase inside the In flight paragraph
- [x] 2.5 Document the paragraph composition templates: show the expected shape for Shipped, In flight, Needs you, and You paragraphs, including the "heads-up" phrasing for collisions and the markdown-link format for PR/branch references
- [x] 2.6 Update the subagent prompt to request one-or-two sentences of prose (suitable as a clause) rather than exactly one sentence as a bullet. The prompt template lives inside §Parallel mode → Dispatch.
- [x] 2.7 Specify the empty-window pass-through: when the script prints `Nothing new since <ISO>`, the skill emits the same line and skips all paragraph composition.
- [x] 2.8 Specify `summary_mode: off` degrades the Shipped paragraph to subject/title prose rather than skipping it.

## 3. SPEC.md rewrite

- [x] 3.1 Replace §Output Format with a new §Output Format describing the narrative prose layout: header, four paragraph roles, order, skip-when-empty, empty-window single line.
- [x] 3.2 Retain §Themes filtering and §Threshold dispatcher as subsections under a new "Shipped paragraph composition" umbrella — their logic still drives diff reads.
- [x] 3.3 Add a new §Collision detection subsection describing the name-overlap and path-overlap rules and the heads-up phrasing.
- [x] 3.4 Add a new §Link rendering subsection describing URL construction for GitHub, GitLab, and unknown forges.
- [x] 3.5 Update §Data Flow to reflect that the script's output is internal scratch and the skill composes prose.
- [x] 3.6 Remove the old "## Merged to …" / "## Merge requests" / "## My activity" / "## MRs awaiting my review" / "## CI on …" section illustrations — moved under §Script internal output as the direct-invocation contract.

## 4. README polish

- [x] 4.1 Update Features list to foreground the narrative output and collision heads-up; demote the mention of structured sections
- [x] 4.2 Replace (or add) an Example block in README showing a sample narrative output
- [x] 4.3 Leave Configuration table unchanged (no new keys; semantics documented elsewhere)

## 5. Acceptance *(PENDING USER VALIDATION)*

Requires a fresh Claude Code session after `/plugin update repo-pulse@repo-pulse`:

- [ ] 5.1 Busy repo: run `/repo-pulse:whats-new --since="1 week ago"` on `/tmp/cli-test`; confirm 3–4 prose paragraphs appear (Shipped, In flight, Needs you, You) with no structured `##` headings other than the header
- [ ] 5.2 Quiet repo: run on the repo-pulse repo itself with a 3-day window; confirm a short one-paragraph output (probably just "You")
- [ ] 5.3 Empty window: run with `--since=1m` or similar; confirm the single-line `Nothing new since <ISO>` passes through
- [ ] 5.4 Collision flag: create a local branch with a name that collides with an open PR's source branch (e.g., `git checkout -b user/test-collision` matching some open PR); rerun; confirm a heads-up phrase appears in the In flight paragraph
- [ ] 5.5 Link rendering: verify PR and branch references in the output render as clickable markdown links in Claude Code's UI
- [ ] 5.6 Unknown forge: run against a Codeberg/Gitea origin; confirm prose renders with plain `#N` / `` `branch` `` text and no broken link wrappers
- [ ] 5.7 `summary_mode: off`: set via `~/.claude/settings.json`; rerun on a busy repo; confirm Shipped paragraph still appears but with title-only prose (no diff-derived clustering)

## 6. Docs final pass

- [x] 6.1 Add a CLAUDE.md gotcha ONLY if something surprising emerges (e.g., markdown-link edge cases on specific terminals). Leave untouched if nothing new. — no new gotcha; markdown links are standard GFM
- [x] 6.2 Confirm all committed artifacts are English-only (grep for Cyrillic across touched files) — zero hits
