## Context

`repo-pulse` v0.1.0 shipped with a two-file shell config (`config.sh` committed template + `config.local.sh` gitignored overrides). That model is fine for a developer running `claude --plugin-dir` against the source tree, but fails the moment the plugin is installed via `/plugin install`:

- The installed copy lives in `~/.claude/plugins/cache/<plugin-id>/`.
- `/plugin update` overwrites the cache from the marketplace source.
- Any `config.local.sh` edits in the cache are therefore erased on every update.

Claude Code's documented solution is `userConfig` in `plugin.json` (see https://code.claude.com/docs/en/plugins-reference.md § "User configuration"). The harness prompts on first enable, stores values in `~/.claude/settings.json` under `pluginConfigs.<id>.options`, and exposes them to subprocesses as `CLAUDE_PLUGIN_OPTION_<KEY>` env vars. `settings.json` lives outside the plugin cache, so values survive updates and reinstalls.

Separately, the user identified a UX win: `git config user.email` already provides the right email per repository (via git's natural config inheritance — `.git/config` → `~/.gitconfig` → system). Using it as the base identity means a first-time user with zero config still gets a usable "My activity" section and a working smart-default window.

## Goals / Non-Goals

**Goals:**
- Make `repo-pulse` publishable as a marketplace plugin without lying about the config UX.
- Zero-config first run on any repo where `git config user.email` is set (which is virtually always).
- Let users extend the effective email list with old/personal addresses via a single CSV string.
- Keep the dev workflow (`claude --plugin-dir ...`) working unchanged.

**Non-Goals** (see `proposal.md` §Non-goals for the full list): list/array `userConfig` types, in-script helpers for mutating settings.json, override mechanism for `git config user.email`, `${user_config.KEY}` substitution in `SKILL.md`.

## Decisions

### D1: Drop `config.sh` / `config.local.sh` entirely

**Alternatives considered:**
- **Keep the files as an additional override path** (env vars first, then shell files if present). Would preserve the dev workflow for users who prefer a file and let marketplace installs use env vars.
- **Write a migration shim** that reads `config.local.sh` once and offers to populate `userConfig` from it.

**Choice:** remove both files. No fallback layer.
**Rationale:** two sources of truth for the same data is the worst outcome — users won't know which wins, and bugs hide there. v0.1.0 has no real users, so there's no migration cost. Dev workflow still works because env vars are set by the harness regardless of how the plugin was loaded (dev-mode behavior is validated in Task 1.4 — if the harness doesn't set env vars in dev-mode, we'll revisit before apply completes).

### D2: Native string array via `multiple: true` for `extra_emails`

**Discovered during apply (Task 1.1):** The `userConfig` schema supports `multiple: true` on `string` fields — the harness exposes a proper "add another value" UI and stores an array in `settings.json`. This is strictly better than any CSV-in-a-string encoding.

**Alternatives considered:**
- Multiple scalar fields (`extra_email_1`, `extra_email_2`, …). Ugly and hard-capped.
- CSV in a single string. Works but forces users to escape commas / trim whitespace themselves.
- JSON-encoded array string. Unfriendly in a prompt.

**Choice:** `{ "type": "string", "multiple": true }`.
**Rationale:** best UX — the harness handles the list affordance itself, `settings.json` stores a typed array, and the user never has to think about separators.

**Env-var encoding uncertainty:** The docs don't specify how `multiple` arrays serialize into `CLAUDE_PLUGIN_OPTION_*`. Safe plan: the script parses defensively — if the value looks like a JSON array (`[...]`) use `jq -r '.[]'`, otherwise split on whitespace/comma/newline. That way the script works no matter which encoding the harness picks.

### D3: Case-insensitive dedup of the effective email list

**Choice:** compare `[git_email] ∪ EXTRA_EMAILS` case-insensitively when deduping.
**Rationale:** `John@Example.com` and `john@example.com` should not produce a 2-element list. Bash 3 (macOS default) doesn't have native case-insensitive comparison for arrays; implement by lowercasing both sides before the compare. (Don't lowercase the stored form — keep the original casing for display in the output header.)

### D4: Identity is git email + extras (union), not extras as override

**Choice:** extras are *additional*, never a replacement for `git config user.email`.
**Rationale:** matches the user's mental model ("розширити"), and the contextual-identity-per-repo benefit only works if git's email is always in the set. If someone truly needs to hide their git email from identity resolution (rare edge case), they can unset `git config --unset user.email` for that repo or use `--since=<value>` to sidestep identity-based window resolution entirely.

### D5: Keep `DEFAULT_SINCE` in `userConfig` too

**Alternatives considered:** hardcode `"7 days ago"` in the script and skip making it configurable.
**Choice:** keep it configurable via `userConfig.default_since`.
**Rationale:** users with quiet repos want longer windows by default; users with very active repos want shorter. Changing this is a one-line edit in `/plugin config`. No reason to force a code change. Default value `"7 days ago"` covers 90% of cases.

### D6: Version bump to `0.2.0`, not `0.1.1`

**Choice:** `0.2.0` (minor bump), marked BREAKING in the proposal.
**Rationale:** the config surface changes in a backwards-incompatible way. Semver says that's a major bump, but we're pre-1.0 so the common convention is to bump the minor digit for breaking changes. `0.2.0` signals "different enough to check your setup" without claiming the API is stable.

### D7: Identity resolution lives in the script, not as a skill-level pre-step

**Alternatives considered:** let Claude resolve emails from `/plugin config` output and pass them to the script via `--my-emails=...` argument.
**Choice:** script does its own resolution from env vars.
**Rationale:** keeps the script self-contained — it works the same whether invoked by the skill, by a human at the shell, or by a future CI hook. The skill stays a thin wrapper.

## Risks / Trade-offs

- **Risk:** `userConfig` might not be set in dev-mode (`--plugin-dir`).
  → **Mitigation:** Task 1.4 runs a spike: load the plugin with `--plugin-dir`, inspect `env | grep CLAUDE_PLUGIN_OPTION_`. If dev-mode doesn't populate env vars, we add a dev-only fallback that reads from `skills/whats-new/config.local.sh` **in dev mode only** (i.e., when `CLAUDE_PLUGIN_DATA` is unset or points inside the source tree). Document the fallback as a dev convenience, not a user-facing feature.
- **Risk:** bot-managed repos (CI containers) have `git config user.email = ci-bot@...`, causing the script to treat bot commits as the user's.
  → **Mitigation:** document as a known edge case in `README.md`; users can `git config --unset user.email` for that repo if it matters. Not worth an `IGNORE_EMAILS` field.
- **Risk:** `git config user.email` unset entirely. Rare (git usually refuses to commit without it), but possible in read-only clones.
  → **Mitigation:** fall through to the EXTRA_EMAILS-only path. If both are empty, emit a `> note:` and fall back to `DEFAULT_SINCE`, matching v0.1.0's "empty MY_EMAILS" behavior.
- **Risk:** CSV parsing surprises (emails with trailing whitespace, empty tokens from `",a@b,"`, etc.).
  → **Mitigation:** trim each token and drop empties. One loop, tested during apply.
- **Risk:** `userConfig` UI might require re-prompting if the schema changes later.
  → **Mitigation:** pick field names carefully now; document them in `SPEC.md` so future changes are deliberate.
- **Risk:** the removed `config.sh` / `config.local.sh` files leave a dangling reference somewhere in docs or scripts.
  → **Mitigation:** Task 5.1 greps the repo for leftover references before merging.

## Migration Plan

There's nothing to migrate — no external users. Steps in order:

1. Validate `userConfig` in dev-mode (Task 1.4). If it doesn't populate env vars, add the dev-mode shell-file fallback and document it.
2. Land the `plugin.json` userConfig block.
3. Rewrite the script's config-sourcing + identity resolution.
4. Delete the two config files. Remove `.gitignore` entry.
5. Update docs.
6. Manual acceptance: install the plugin fresh via `/plugin marketplace add` + `/plugin install`, confirm first-run prompt, run the slash command, tweak via `/plugin config`, re-run.

Rollback: `git revert` the change. If already on a user machine, `/plugin uninstall` and reinstall v0.1.0.

## Open Questions

- **Post-install edit UX.** Is the canonical way to change `userConfig` values after first enable `/plugin config <plugin-id>`, direct edit of `~/.claude/settings.json`, or both? Task 6.3 tests this end-to-end so we can document the actual UX.
- **Does `userConfig` show up in `/plugin config` with field titles/descriptions?** Affects whether the `description` text is wasted or not. Acceptance will tell us.
- **What happens if `default_since` is an invalid git-since value** (e.g., user types `"soon"` into the prompt)? Currently the script would fall back to git's own approxidate, which may misparse. Do we validate? For v0.2.0 we accept whatever the user types; for v0.3.0 we could add a pre-flight validation (run `date -d "${value}"` once at startup and emit a `> note:` on failure).
