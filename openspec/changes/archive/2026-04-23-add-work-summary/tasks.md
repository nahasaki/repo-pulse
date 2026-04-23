## 1. Script — themes-metadata emission

- [x] 1.1 Add helper function in `whats-new.sh` that, given the list of §1 commit SHAs, runs `git log --shortstat --pretty='…'` once and builds a `sha,author,added,deleted,files` CSV row per commit
- [x] 1.2 Append the `<!-- themes-metadata … -->` HTML comment block to the end of the script's output when §1 has commits; emit nothing when §1 is empty
- [x] 1.3 Verify the block is invisible in rendered markdown (eyeball-check output in a grep-friendly way) and keep it after the existing trailing newline
- [x] 1.4 Preserve the `chmod +x` bit on `whats-new.sh` (no change needed but verify after edit)
- [x] 1.5 Run the script against `/tmp/cli-test` and confirm the metadata block matches §1 count exactly

## 2. Plugin manifest — userConfig knobs

- [x] 2.1 Add `summary_mode` to `.claude-plugin/plugin.json` userConfig with enum `auto|off|always`, default `auto`, with description text
- [x] 2.2 Add `summary_max_commits` to userConfig with integer type, default 50, with description text (stored as string type because env vars are strings; skill parses to int)
- [x] 2.3 Bump `version` in `.claude-plugin/plugin.json` from `0.3.0` to `0.4.0`
- [x] 2.4 Run `claude plugin validate .claude-plugin/plugin.json` and confirm it passes with no errors

## 3. Skill — step 2 expansion

- [x] 3.1 Rewrite step 2 of `SKILL.md` to describe the full filter → cluster → threshold → summarize → prepend pipeline
- [x] 3.2 Document the named constants (`SERIAL_N_CAP=10`, `SERIAL_DIFF_KB_CAP=50`, `PARALLEL_CONCURRENCY=8`, `OUTPUT_BULLET_CAP=6`) in a visible block at the top of the skill's implementation section
- [x] 3.3 Document the filtering rules from the delta spec (bot authors, lock/vendor-only, trivial dep bumps, merge commits, docs-only) with exact patterns
- [x] 3.4 Document the clustering rule `(author, conventional-commit-type, top-level-path)` with examples
- [x] 3.5 Document the three dispatch modes (`skip`, `serial`, `parallel`) with exact thresholds and behavior
- [x] 3.6 Document the fixed subagent prompt template (from design.md D4) with the tool-scoping rule (`Bash(git:*)` only) and the 30-line-per-diff cap
- [x] 3.7 Document the degraded-output note rules (≥ 25% subagent failures → `> note:` emitted)
- [x] 3.8 Document the fallback when `themes-metadata` block is missing (call `git log --shortstat` from the skill)
- [x] 3.9 Document the output format (3–6 bullets, exactly one sentence per bullet, bold title, `(N commits, author…)` mechanical prefix, no emoji)

## 4. SPEC.md updates

- [x] 4.1 Update §Output to document the Themes section — position (above §1), bullet format, 3–6 cap, one sentence rule
- [x] 4.2 Update §Configuration to document the two new userConfig keys (`summary_mode`, `summary_max_commits`) with defaults and semantics
- [x] 4.3 Add a short subsection (under §Output or §Implementation) on the filtering rules for themes
- [x] 4.4 Add a short subsection on the threshold dispatcher (serial vs parallel vs skip)
- [x] 4.5 Document the `themes-metadata` HTML-comment block as part of the script output contract
- [x] 4.6 Cross-reference from the capability spec delta back to SPEC.md sections (not duplicate content) — delta spec already cross-references SPEC.md concepts without duplication

## 5. Implementation — skill script (themes generation in SKILL.md)

- [x] 5.1 Parse the `themes-metadata` block from the script's output; on missing block, fall back to `git log --shortstat` with the same window *(in SKILL.md §Themes pipeline — Inputs)*
- [x] 5.2 Apply all five filtering rules; compute `N` and `DIFF_KB` *(in SKILL.md §Themes pipeline — Filtering & Signals)*
- [x] 5.3 Implement the threshold decision (`skip` / `serial` / `parallel`) and branch accordingly; honor `summary_mode` override and `summary_max_commits` cap *(in SKILL.md §Themes pipeline — Dispatch)*
- [x] 5.4 Implement clustering `(author, type, path)` with handling for `<mixed>` top-level-path and `other` type fallback *(in SKILL.md §Themes pipeline — Clustering)*
- [x] 5.5 Implement `serial` mode: `git show <sha>` per commit inside the host session, produce cluster summaries, stitch into the themes section *(in SKILL.md §Themes pipeline — Serial mode)*
- [x] 5.6 Implement `parallel` mode: `Task` tool dispatch in batches of 8 with the fixed prompt template, graceful failure handling, and the ≥ 25% degradation note *(in SKILL.md §Themes pipeline — Parallel mode & Graceful degradation)*
- [x] 5.7 Render the final themes section (3–6 bullets, author truncation to `author1 + author2 + others` when three or more), prepend above §1 in the script's output, and print the composed markdown *(in SKILL.md §Themes pipeline — Rendering the themes section)*

## 6. Acceptance — quiet repo (serial path) *(PENDING USER VALIDATION)*

Requires a fresh Claude Code session after `/plugin update` to exercise
the live SKILL.md against a small repo. Cannot be simulated from the
authoring session.

- [ ] 6.1 Run `/repo-pulse:whats-new --since=3d` on a repo with ~5 eligible commits across 2 authors; confirm themes section appears with 2 bullets and `serial` path runs without spawning subagents
- [ ] 6.2 Verify the filtering correctly excludes any dependabot or lock-file-only commits present
- [ ] 6.3 Run with `summary_mode=off` (set via `~/.claude/settings.json`) and confirm no themes section appears
- [ ] 6.4 Run with `summary_mode=always` on the same quiet repo and confirm it runs in `parallel` mode (evidenced by subagent dispatch in trace)

## 7. Acceptance — busy repo (parallel path) *(PENDING USER VALIDATION)*

Same constraint as §6 — requires a fresh interactive session.

- [ ] 7.1 Run on `/tmp/cli-test` with `--since="1 week ago"` — should have 30+ commits and trigger `parallel` mode; confirm themes section appears with 3–6 bullets
- [ ] 7.2 Confirm clusters make intuitive sense — same-author same-type bundled together, different areas split apart
- [ ] 7.3 Confirm main-session context does not contain raw diff text (verify via trace: only subagent summaries came back)

## 8. Acceptance — edge cases *(PENDING USER VALIDATION)*

- [ ] 8.1 Run with `summary_max_commits=10` on a busy repo (N > 10) and confirm the cap note appears with the exact suggested format
- [ ] 8.2 Run on a repo with only dependabot bumps for the window (`N == 0` post-filter) and confirm no themes section appears and no error is raised
- [ ] 8.3 Run on a docs-only commit window and confirm no themes section appears (all commits filtered)
- [ ] 8.4 Simulate a subagent failure (force one cluster's prompt to fail) in a `parallel` run and confirm the skill continues with remaining bullets and emits the degradation note when threshold reached

## 9. Docs polish

- [x] 9.1 Update `README.md` Features list to mention the themes section as a headline capability
- [x] 9.2 Update `README.md` Configuration table to include the two new keys
- [x] 9.3 Update `CLAUDE.md` if any new gotchas emerged during implementation (leave empty if none) — added userConfig-values-are-strings gotcha
- [x] 9.4 Confirm all committed artifacts are English-only (no Ukrainian text in code, comments, docs, or commit messages) — grep for Cyrillic across all touched files returned no hits
