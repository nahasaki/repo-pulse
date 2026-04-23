## 1. Validation spike

- [x] 1.1 Read https://code.claude.com/docs/en/plugins-reference.md §"User configuration" end-to-end. Confirmed: types are `string | number | boolean | directory | file`; env var name is `CLAUDE_PLUGIN_OPTION_<KEY>`; values persist in `~/.claude/settings.json` under `pluginConfigs[<plugin-id>].options` (sensitive values go to keychain). Surprise: `multiple: true` is supported for `string` type → native array UI, which is strictly better than CSV. Updated `design.md` §D2. Docs do NOT specify whether userConfig prompts fire in `--plugin-dir` dev-mode, nor the env-var encoding of `multiple: true` values — script parses defensively, and Tasks 1.2–1.4 remain user-validated.
- [ ] 1.2 **PENDING USER VALIDATION.** Cannot be run from inside a Claude Code session. In a fresh terminal, install a throwaway plugin that declares one `userConfig` field, enable it, and `env | grep CLAUDE_PLUGIN_OPTION_` inside its script to confirm the env var arrives populated. If it does not, report back — the current implementation assumes env vars reach the subprocess.
- [ ] 1.3 **PENDING USER VALIDATION.** Same as 1.2 but via `claude --plugin-dir ~/Projects/claude-plugins/repo-pulse` to check dev-mode behavior. If env vars are unset in dev-mode, the script already falls back to sourcing `skills/whats-new/config.local.sh` (a user-authored, gitignored file) and emits a `> note:` — so dev-mode still works without marketplace install.
- [ ] 1.4 **PENDING USER VALIDATION.** Test the real post-install edit verb (`/plugin config <id>`, direct edit of `settings.json`, or whatever exists). Document findings in `README.md` §Configuration.

## 2. Plugin manifest

- [x] 2.1 Updated `.claude-plugin/plugin.json`: version bumped to `0.2.0`; added `userConfig` with `extra_emails` (`type: string, multiple: true, default: []`) and `default_since` (`type: string, default: "7 days ago"`), each with clear title + description for the first-run prompt.

## 3. Script rewrite

- [x] 3.1 Replaced the config-sourcing block with env-var reads (`CLAUDE_PLUGIN_OPTION_DEFAULT_SINCE`, `CLAUDE_PLUGIN_OPTION_EXTRA_EMAILS`) using bash `:-` defaults. Old `. config.sh` / `. config.local.sh` lines deleted from the production path.
- [x] 3.2 Implemented `parse_extras` (handles JSON-array, CSV, and newline-separated forms, since docs don't specify how `multiple: true` serializes). Built `EFFECTIVE_EMAILS` = `[git config user.email] ∪ EXTRA_EMAILS_RESOLVED` with case-insensitive dedup that preserves original casing.
- [x] 3.3 The `build_email_regex` function now reads from `EFFECTIVE_EMAILS`. The v0.1.0 `MY_EMAILS` array name is gone from the production path (kept only as a dev-mode input the fallback might encounter if a user still has an old-style `config.local.sh`; the fallback prefers `EXTRA_EMAILS` array).
- [x] 3.4 Removed the `MY_EMAILS is empty` note. The earlier "no identity at all" note (emitted when `EFFECTIVE_EMAILS` is empty) covers the blank-section-4 case; the window-resolution fallback no longer emits a duplicate.
- [x] 3.5 Added conservative dev-mode fallback: if neither `CLAUDE_PLUGIN_OPTION_*` env var is set AND `skills/whats-new/config.local.sh` exists, source it and emit `> note: dev-mode: loaded config from ...`. The fallback reads `EXTRA_EMAILS` as a bash array if config.local.sh declares it. This protects against the unverified case (Task 1.3) where `--plugin-dir` might not populate env vars; it's a no-op in the production path.

## 4. Remove obsolete files

- [x] 4.1 Deleted `skills/whats-new/config.sh` and `skills/whats-new/config.local.sh`. Used `rm` (not `git rm`) because the v0.1.0 files were never committed in this repo (gitStatus at session start showed the plugin tree as untracked; only `SPEC.md`, `README.md`, `CLAUDE.md`, `.gitignore` were staged). Nothing for history to preserve.
- [x] 4.2 **Kept** the `**/config.local.sh` entry in `.gitignore`. The dev-mode fallback (Task 3.5) still reads a user-authored `config.local.sh` if env vars are unset; the entry prevents a dev from accidentally committing their personal emails. This deviates from the original task intent, but matches the spec (the plugin does not SHIP config.local.sh, and the fallback is for user-authored local files).

## 5. Documentation sweep

- [x] 5.1 Grep-verified: no remaining `MY_EMAILS` or `config.sh` references in `SPEC.md`, `README.md`, `CLAUDE.md`, `skills/`. The only remaining `config.local.sh` mentions are in dev-mode-fallback context, which is intentional.
- [x] 5.2 Rewrote `SPEC.md` §Configuration: describes the `userConfig` block (two fields + table), effective email formula (`[git user.email] ∪ extra_emails`), and a dedicated subsection on the dev-mode fallback. §File Layout no longer lists shell config files.
- [x] 5.3 Rewrote `README.md` §Configuration: zero-config narrative, first-run prompt description, and a pointer to SPEC.md for the dev-mode fallback. The exact post-install edit command remains TBD (Task 1.4 pending) — the README currently says "re-run the plugin's config flow in Claude Code (or edit settings.json directly)".
- [x] 5.4 Updated `CLAUDE.md`: layout dropped `config.sh`; added a short "user config lives in plugin.json userConfig" note; replaced the v0.1.0 implementation checklist with a reference to the archived change + current spec, since those plans are now executed.
- [x] 5.5 Updated `SKILL.md`: `MY_EMAILS` note replaced with "no git user.email and extra_emails empty", pointing the user at the plugin-config UI or `~/.claude/settings.json`.

## 6. Acceptance

- [ ] 6.1 **PENDING USER VALIDATION.** Cannot initiate a Claude Code session from inside this session. Steps for you to run: `/plugin marketplace add ~/Projects/claude-plugins/repo-pulse`, then `/plugin install repo-pulse@repo-pulse`. On first enable, confirm the prompt shows `extra_emails` (with a list-add affordance since `multiple: true`) and `default_since`, with the titles/descriptions from `plugin.json`.
- [x] 6.2 Ran the script directly against `~/Projects/promin/funnels-builder` with `CLAUDE_PLUGIN_OPTION_EXTRA_EMAILS=""` (no extras) and no dev-mode fallback file. Output: `## My activity (69 commits across 14 branches)` — section 4 populated using only `git config user.email` (`m.tantsyura@promin-apps.com`). Zero-config path works end to end.
- [ ] 6.3 **PENDING USER VALIDATION.** After first enable, add a second email via the post-install config flow (command TBD by Task 1.4). Re-run `/repo-pulse:whats-new`; section 4 should pick up commits authored with the added address.
- [ ] 6.4 **PENDING USER VALIDATION.** After setting `extra_emails` and `default_since`, run `/plugin update repo-pulse@repo-pulse`. Confirm values still present in `~/.claude/settings.json` under `pluginConfigs."repo-pulse".options` and the user is NOT re-prompted.
- [x] 6.5 Ran in a scratch repo with `git config user.email` unset (both local and global temporarily — restored after). Output: the expected `> note: no git user.email set and extra_emails is empty — section 4 will be blank; window falls back to DEFAULT_SINCE`, then `Nothing new since <ISO>`, exit 0. Matches spec.
