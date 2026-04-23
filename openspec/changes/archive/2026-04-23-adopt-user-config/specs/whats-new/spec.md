## MODIFIED Requirements

### Requirement: Window resolution

The system SHALL determine the effective author identity and the window start as follows:

**Effective author identity** (`EFFECTIVE_EMAILS`):
1. Start with `git config user.email` for the current repository (empty string if unset).
2. Append each non-empty, trimmed token from the comma-separated `${CLAUDE_PLUGIN_OPTION_EXTRA_EMAILS}` env var.
3. Deduplicate case-insensitively, preserving original casing for display.

**Window start**:
1. If `--since` is provided, use its value.
2. Else, find the most recent commit across all refs whose author email matches any entry in `EFFECTIVE_EMAILS` (case-insensitive), and use that commit's **committer date** as the window start.
3. Else, fall back to `${CLAUDE_PLUGIN_OPTION_DEFAULT_SINCE}` (default `"7 days ago"`) from the plugin's user config.

All time comparisons throughout the system SHALL use committer date, never author date.

#### Scenario: git user.email alone is enough

- **WHEN** a user with no `extra_emails` configured runs the plugin in a repo where `git config user.email` returns `me@work.com`
- **AND** the user has at least one commit authored with `me@work.com`
- **THEN** `EFFECTIVE_EMAILS` equals `["me@work.com"]`
- **AND** the window start equals that commit's committer date
- **AND** the output header's `<reason>` reads `from your last commit on <ISO date>`

#### Scenario: git user.email plus extras

- **WHEN** `git config user.email` returns `me@work.com`
- **AND** `${CLAUDE_PLUGIN_OPTION_EXTRA_EMAILS}` is `"me@personal.com, old@former-job.com"`
- **THEN** `EFFECTIVE_EMAILS` equals `["me@work.com", "me@personal.com", "old@former-job.com"]`
- **AND** the most recent commit across any of those three addresses is used as the window anchor

#### Scenario: git user.email overlap with extras

- **WHEN** `git config user.email` returns `Me@Work.COM`
- **AND** `${CLAUDE_PLUGIN_OPTION_EXTRA_EMAILS}` is `"me@work.com, other@addr.com"`
- **THEN** case-insensitive dedup removes the duplicate
- **AND** `EFFECTIVE_EMAILS` equals `["Me@Work.COM", "other@addr.com"]` (two entries, original casing preserved)

#### Scenario: no identity anywhere

- **WHEN** `git config user.email` is unset **AND** `${CLAUDE_PLUGIN_OPTION_EXTRA_EMAILS}` is empty
- **THEN** `EFFECTIVE_EMAILS` is empty
- **AND** the window start falls back to `now − DEFAULT_SINCE`
- **AND** the output header's `<reason>` reads `DEFAULT_SINCE fallback (<value>)`
- **AND** a `> note:` warning announces that neither git user.email nor extra_emails is set

#### Scenario: explicit --since overrides identity resolution

- **WHEN** the user runs `/repo-pulse:whats-new --since=3d`
- **THEN** identity resolution still happens for filtering sections 1, 2, and 4
- **BUT** the window start is unconditionally three days before now
- **AND** the output header's `<reason>` reads `--since=3d`

## REMOVED Requirements

### Requirement: Configuration via template plus local override

**Reason**: Superseded by Claude Code's built-in `userConfig` mechanism, which survives plugin updates (values live in `~/.claude/settings.json`, not in the plugin cache that `/plugin update` overwrites) and provides a harness-driven first-run prompt instead of hand-editing shell files.

**Migration**: v0.1.0 had no external users. On update, the harness prompts for `extra_emails` and `default_since` values when the user next enables the plugin. Existing `skills/whats-new/config.sh` and `skills/whats-new/config.local.sh` files are deleted from the repo.

## ADDED Requirements

### Requirement: Configuration via plugin userConfig

The plugin SHALL declare its user-configurable parameters via the `userConfig` block in `.claude-plugin/plugin.json`. The Claude Code harness prompts the user for these values on first enable, persists them in `~/.claude/settings.json` under `pluginConfigs."repo-pulse".options`, and exposes them to the script as `CLAUDE_PLUGIN_OPTION_<KEY>` environment variables.

The plugin SHALL declare exactly these fields:

| Field | Type | Default | Purpose |
|---|---|---|---|
| `extra_emails` | string | `""` | Comma-separated additional author emails beyond `git config user.email` |
| `default_since` | string | `"7 days ago"` | Fallback window when no last commit can be detected |

The plugin SHALL NOT ship any `config.sh`, `config.local.sh`, or other shell-sourced config files inside the plugin tree. All user-tunable values flow through `userConfig`.

The script SHALL read configuration exclusively from environment variables, with bash defaults applied when a variable is unset:

```bash
DEFAULT_SINCE="${CLAUDE_PLUGIN_OPTION_DEFAULT_SINCE:-7 days ago}"
RAW_EXTRAS="${CLAUDE_PLUGIN_OPTION_EXTRA_EMAILS:-}"
```

Empty `extra_emails` is valid — it means "no additional emails beyond git user.email".

#### Scenario: First-run prompt on enable

- **WHEN** the user installs the plugin and enables it for the first time
- **THEN** the Claude Code harness displays a prompt for `extra_emails` and `default_since`, populated with the declared defaults
- **AND** the values are persisted to `~/.claude/settings.json` under `pluginConfigs."repo-pulse".options`

#### Scenario: Values reach the script as env vars

- **WHEN** the user has `extra_emails = "foo@bar.com,baz@qux.com"` and `default_since = "14 days ago"` in their settings
- **AND** the script runs
- **THEN** `CLAUDE_PLUGIN_OPTION_EXTRA_EMAILS` equals `"foo@bar.com,baz@qux.com"`
- **AND** `CLAUDE_PLUGIN_OPTION_DEFAULT_SINCE` equals `"14 days ago"`

#### Scenario: Survives plugin update

- **WHEN** the user has configured `extra_emails` and then runs `/plugin update repo-pulse`
- **THEN** the settings persist — the user is NOT re-prompted and existing values remain valid
- **AND** the plugin cache at `~/.claude/plugins/cache/<id>/` may be overwritten without affecting config

#### Scenario: Missing env vars use script defaults

- **WHEN** the script runs in an environment where `CLAUDE_PLUGIN_OPTION_*` is not set (e.g., the user bypassed the harness prompt, or the plugin was loaded in an unusual dev-mode configuration)
- **THEN** `DEFAULT_SINCE` defaults to `"7 days ago"` via bash `:-` expansion
- **AND** `extra_emails` is treated as empty
- **AND** the script still runs end-to-end
