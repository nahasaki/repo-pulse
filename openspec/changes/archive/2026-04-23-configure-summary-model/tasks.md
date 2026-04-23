## 1. Plugin manifest — userConfig + version bump

- [x] 1.1 Add `summary_model` to `.claude-plugin/plugin.json` userConfig as `string` type, default `"haiku"`, with description listing allowed values (`haiku | sonnet | opus | inherit`) and explicitly noting parallel-only scope
- [x] 1.2 Bump `version` in `.claude-plugin/plugin.json` from `0.4.0` to `0.5.0`
- [x] 1.3 Run `claude plugin validate .claude-plugin/plugin.json` and confirm it passes

## 2. Skill — SKILL.md parallel-mode update

- [x] 2.1 Add a "Model selection" subsection under §Parallel mode in `SKILL.md` that: (a) reads `CLAUDE_PLUGIN_OPTION_SUMMARY_MODEL` with default `haiku`, (b) validates against `{haiku, sonnet, opus, inherit}`, (c) on invalid value falls back to `inherit` and emits a `> note: unknown summary_model value '<value>'; falling back to host session model`
- [x] 2.2 Update the parallel-mode dispatch example/template in `SKILL.md` to include `model: <value>` on each `Task` call, with an explicit note that `inherit` means "omit the `model` field"
- [x] 2.3 Verify the existing serial-mode documentation makes it clear that `summary_model` does NOT apply there; add one sentence if needed — added a paragraph in §Serial mode stating the host-session-only rule

## 3. SPEC.md updates

- [x] 3.1 Add `summary_model` row to §Configuration table with default `haiku`, allowed values, and parallel-only note
- [x] 3.2 Add a short paragraph in §Configuration or near the themes documentation explaining the parallel-only scope — added §Themes model selection (parallel mode only)
- [x] 3.3 Update the threshold dispatcher subsection if needed to reference the new knob (no logic change — just cross-reference) — new §Themes model selection subsection follows the dispatcher section directly, cross-referencing it via placement

## 4. README polish

- [x] 4.1 Add `summary_model` row to README Configuration table
- [x] 4.2 Mention the "cheap by default" angle briefly in Features list (optional — skip if it feels like noise) — skipped; the configuration table already conveys "default haiku" and the Features list already has a line about themes being "cheap on quiet repos, bounded on busy ones"

## 5. Acceptance *(PENDING USER VALIDATION)*

Requires a fresh Claude Code session after `/plugin update repo-pulse@repo-pulse`:

- [ ] 5.1 Default case: do nothing to config; run `/repo-pulse:whats-new --since="1 week ago"` on `/tmp/cli-test`. Confirm via trace that subagents were dispatched with `model: "haiku"`
- [ ] 5.2 Override: set `summary_model: sonnet` via `~/.claude/settings.json`; rerun; confirm subagents dispatched with `model: "sonnet"`
- [ ] 5.3 Inherit: set `summary_model: inherit`; rerun; confirm `Task` invocations omit the `model` field and subagents run on the host session's model
- [ ] 5.4 Invalid value: set `summary_model: gpt-4`; rerun; confirm `> note:` is emitted and themes still generate using host session model
- [ ] 5.5 Serial-mode independence: on a quiet repo (N ≤ 10) with `summary_model: haiku`, confirm no subagents dispatched and themes generated in host session regardless of the config

## 6. Docs final pass

- [x] 6.1 Add a CLAUDE.md gotcha ONLY if something surprising emerges (e.g., `Task` tool rejecting a valid value). Leave untouched if nothing new. — no new gotcha; Task's `model` parameter works as documented
- [x] 6.2 Confirm all committed artifacts are English-only — grep for Cyrillic across all touched files returned no hits
