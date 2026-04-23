## Why

v0.1.0 stores user config in two shell files shipped inside the plugin tree (`skills/whats-new/config.sh`, `skills/whats-new/config.local.sh`). That works in dev (`claude --plugin-dir`), but breaks the moment the plugin is installed from a marketplace: `/plugin install` copies the plugin into `~/.claude/plugins/cache/<id>/`, which is overwritten on every update — so any user edits to `config.local.sh` vanish silently on `/plugin update`. First-run UX is also bad: the user has to locate the cache path, open a shell file, edit it, save. None of that is discoverable.

Claude Code already has a canonical mechanism for exactly this — `userConfig` in `plugin.json`. The harness prompts on first enable, persists values in `~/.claude/settings.json` (outside the cache, survives updates), and exposes them to scripts as `CLAUDE_PLUGIN_OPTION_<KEY>` env vars. Adopting it turns repo-pulse into a publish-ready plugin instead of a dev-only one.

While we're rewriting the config layer, we can also fix a related UX nit: the smart-default window needs at least one known email to work, but `git config user.email` already gives us the right email for each repo. Using it as the base identity and treating the plugin config as *extra* addresses (for old accounts, personal/work splits) means the plugin works out of the box with zero config on a fresh install.

## What Changes

- **Remove** `skills/whats-new/config.sh` and `skills/whats-new/config.local.sh`. These files cease to exist.
- **Add** a `userConfig` block to `.claude-plugin/plugin.json` declaring:
  - `extra_emails` (string, CSV) — additional author emails beyond `git config user.email`.
  - `default_since` (string, default `"7 days ago"`) — fallback window.
- **Rewrite identity resolution** in `skills/whats-new/scripts/whats-new.sh`:
  - Base identity = `git config user.email` (per-repo, context-aware).
  - Plus parsed CSV from `${CLAUDE_PLUGIN_OPTION_EXTRA_EMAILS:-}`.
  - Deduplicate, case-insensitive.
  - Fall back to `DEFAULT_SINCE` only when both sources are empty.
- **Update `.gitignore`** — remove the now-obsolete `**/config.local.sh` entry.
- **Bump** `plugin.json` `version` to `0.2.0` (breaking config change).
- **Update docs**: `SPEC.md` §Configuration, `README.md` §Configuration, `CLAUDE.md` §"Persistent state" and §"Implementation Checklist", `SKILL.md` body (remove any reference to config files).
- **BREAKING**: any user who installed v0.1.0 and put emails in `config.local.sh` must re-enter them via `/plugin config` (or first-run prompt) after updating. Since no-one uses v0.1.0 outside the author's machine, the migration cost is zero — but the breaking nature is real and worth marking.

## Capabilities

### New Capabilities

_None — we're modifying the existing `whats-new` capability, not adding new behavior._

### Modified Capabilities

- `whats-new`: identity / configuration requirements are rewritten. `Requirement: Configuration via template plus local override` is replaced by a new `Requirement: Configuration via plugin userConfig`. `Requirement: Window resolution` is updated to describe the effective email list (git user.email ∪ extras).

## Impact

- **Files created**: none (plugin.json already exists; we're editing it).
- **Files modified**: `.claude-plugin/plugin.json`, `skills/whats-new/scripts/whats-new.sh`, `skills/whats-new/SKILL.md`, `SPEC.md`, `README.md`, `CLAUDE.md`, `.gitignore`.
- **Files deleted**: `skills/whats-new/config.sh`, `skills/whats-new/config.local.sh`.
- **Version bump**: `0.1.0` → `0.2.0` (breaking).
- **User-visible change**: first-run prompts on enable; no more "find the config file" step.
- **Dev workflow**: `claude --plugin-dir` still works. `userConfig` in dev mode needs validation — Task 1.4 is a spike to confirm behavior before depending on it.

## Non-goals

- **Array/list types for `userConfig`.** Claude Code's `userConfig` only supports `string | number | boolean | directory | file`. We accept CSV-in-a-string for `extra_emails`; introducing a structured list format is out of scope.
- **A `whats-new --add-email foo@bar.com` helper** that mutates `settings.json`. Tempting but adds JSON-writing complexity and a second source of truth. Users edit via `/plugin config` (or directly in `settings.json`).
- **Removing `git config user.email` from the base.** We treat it as authoritative for per-repo identity; if someone wants to override (e.g., weird bot-setup repos), they change `git config user.email` or pass `--since=<value>` to sidestep identity entirely.
- **Migration of existing `config.local.sh` values** into settings.json. No users to migrate.
- **Exposing `userConfig` values to the SKILL.md body via `${user_config.KEY}`.** Possible per docs, but the script already gets them via env var — duplication not worth the extra docs surface.
