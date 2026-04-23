# whats-new

Summarize activity in the current git repository since the user was last active.

## Requirements

### Requirement: Slash-command invocation

The system SHALL expose a slash command `/repo-pulse:whats-new` that accepts an optional `--since=<period>` argument. The value SHALL accept any string that `git log --since` accepts (e.g., `3d`, `1w`, `"2 weeks ago"`, `2026-04-20`).

#### Scenario: Default invocation with smart window

- **WHEN** the user runs `/repo-pulse:whats-new` with no arguments
- **THEN** the system resolves a window via the smart default
- **AND** emits the six-section markdown summary to stdout

#### Scenario: Explicit --since argument

- **WHEN** the user runs `/repo-pulse:whats-new --since=3d`
- **THEN** the window starts three days before the current time
- **AND** the output header's `<reason>` reads `--since=3d`

### Requirement: Natural-language auto-invocation

The `whats-new` skill SHALL auto-invoke on catch-up prompts such as "what's new in this repo", "catch me up", or "what did the team do while I was away", via the `description` field in `SKILL.md`.

#### Scenario: Catch-me-up phrasing

- **WHEN** the user types "catch me up on this repo"
- **THEN** Claude invokes the `whats-new` skill without requiring the slash-command prefix

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

### Requirement: Six-section markdown output

The system SHALL produce plain markdown to stdout in this fixed section order, omitting any section that is empty:

1. **Merged to default** — commits reachable from `origin/<default>` within the window, authored by someone other than the user, excluding merge commits.
2. **New / updated remote branches** — non-default remote branches whose last commit is within the window, excluding branches whose every in-window commit is by the user. Shows name, last committer name, last commit time, and commits-ahead count relative to the default branch.
3. **Merge requests** — three subsections: "Open — others" (authored by someone else, still open), "Merged this period" (any author, merged in window), "Open — mine" (authored by the user, still open). Each entry: `!<iid> <title> — <author>, <source> → <target>, CI: <status>`.
4. **My activity** — commits across all refs within the window authored by any address in `EFFECTIVE_EMAILS`, grouped by branch then by date.
5. **MRs awaiting my review** — output of `glab mr list --reviewer=@me`; no time filter. Each entry: `!<iid> <title> — <author>, age: <N days>`.
6. **CI on default** — last pipeline on `origin/<default>`: id, status, creation time, and web URL, on one line.

If every section is empty, the system SHALL print a single-line summary `Nothing new since <ISO start>` and nothing else.

**Downstream Claude TL;DR logic depends on this output shape.** Any future change to the section order or format MUST explicitly call that out in the change's proposal.

#### Scenario: All sections empty

- **WHEN** the window contains no colleague activity, no user commits, no MR updates, and no new pipelines
- **THEN** the script prints a single line: `Nothing new since <ISO start>`

#### Scenario: Mixed sections

- **WHEN** sections 1 and 4 have data but sections 2, 3, 5, and 6 are empty
- **THEN** the output includes the "Merged to default" and "My activity" sections, in that order
- **AND** no empty section headers appear

### Requirement: Default-branch auto-detection

The system SHALL detect the repository's default branch by reading `git symbolic-ref refs/remotes/origin/HEAD`. If that command fails or returns nothing, the system SHALL fall back to `main`. There is no user-configurable override.

#### Scenario: origin/HEAD is set

- **WHEN** `git symbolic-ref refs/remotes/origin/HEAD` returns `refs/remotes/origin/develop`
- **THEN** the script treats `develop` as the default branch throughout all sections and in the output header

#### Scenario: origin/HEAD is not set

- **WHEN** the symbolic-ref command fails or returns nothing
- **THEN** the script uses `main` as the default branch

### Requirement: Configuration via plugin userConfig

The plugin SHALL declare its user-configurable parameters via the `userConfig` block in `.claude-plugin/plugin.json`. The Claude Code harness prompts the user for these values on first enable, persists them in `~/.claude/settings.json` under `pluginConfigs."repo-pulse".options`, and exposes them to the script as `CLAUDE_PLUGIN_OPTION_<KEY>` environment variables.

The plugin SHALL declare exactly these fields:

| Field | Type | Default | Purpose |
|---|---|---|---|
| `extra_emails` | string (`multiple: true`) | `[]` | Additional author emails beyond `git config user.email` |
| `default_since` | string | `"7 days ago"` | Fallback window when no last commit can be detected |

The plugin SHALL NOT ship any `config.sh`, `config.local.sh`, or other shell-sourced config files inside the plugin tree. All user-tunable values flow through `userConfig`.

The script SHALL read configuration exclusively from environment variables, with bash defaults applied when a variable is unset:

```bash
DEFAULT_SINCE="${CLAUDE_PLUGIN_OPTION_DEFAULT_SINCE:-7 days ago}"
RAW_EXTRAS="${CLAUDE_PLUGIN_OPTION_EXTRA_EMAILS:-}"
```

Empty `extra_emails` is valid — it means "no additional emails beyond git user.email".

A user-authored `skills/whats-new/config.local.sh` (gitignored, not shipped) MAY be sourced as a dev-mode fallback when `CLAUDE_PLUGIN_OPTION_*` env vars are unset — this applies only to `claude --plugin-dir` sessions where the harness may not populate env vars, and the script emits a `> note:` whenever the fallback activates.

#### Scenario: First-run prompt on enable

- **WHEN** the user installs the plugin and enables it for the first time
- **THEN** the Claude Code harness displays a prompt for `extra_emails` and `default_since`, populated with the declared defaults
- **AND** the values are persisted to `~/.claude/settings.json` under `pluginConfigs."repo-pulse".options`

#### Scenario: Values reach the script as env vars

- **WHEN** the user has `extra_emails = ["foo@bar.com", "baz@qux.com"]` and `default_since = "14 days ago"` in their settings
- **AND** the script runs
- **THEN** `CLAUDE_PLUGIN_OPTION_EXTRA_EMAILS` carries both addresses (in whatever encoding the harness chooses)
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

### Requirement: Read-only operation on the repository

The system SHALL NOT mutate the repository in any way except for running `git fetch --all --prune --quiet` once at startup. The system SHALL NOT write any files inside the plugin's own directory at runtime.

#### Scenario: Only fetch mutates refs

- **WHEN** the script runs to completion
- **THEN** the only side effect on the repository is the refs updated by `git fetch`
- **AND** no files are created, modified, or deleted inside `${CLAUDE_PLUGIN_ROOT}`

### Requirement: Preflight and graceful degradation

The system SHALL handle preflight failures as specified:

| Condition | Behavior |
|---|---|
| Not in a git work tree | One-line message to stderr, exit 1 |
| Origin is not a GitLab remote | Print `> note:` warning; run git-only sections (1, 2, 4) |
| `glab auth status` fails | Same as non-GitLab: warn, run git-only sections |
| `git fetch` fails (offline) | Print `> note:` warning; continue against stale refs |
| `jq` missing, origin is GitLab | Exit 1 with an install hint |
| `jq` missing, origin is not GitLab | Warn; skip glab-dependent sections |

All non-fatal warnings SHALL be emitted as lines prefixed with `> note:` at the top of the output so Claude surfaces them to the user without treating them as data.

#### Scenario: Non-GitLab origin

- **WHEN** the origin remote points to a non-GitLab host (e.g., `github.com:foo/bar`)
- **THEN** the output starts with a `> note:` warning identifying the non-GitLab origin
- **AND** only sections 1 ("Merged to default"), 2 ("Remote branches"), and 4 ("My activity") are produced
- **AND** the exit status is 0

#### Scenario: Offline run

- **WHEN** `git fetch --all --prune --quiet` exits non-zero
- **THEN** a `> note:` warning about the fetch failure is printed at the top of the output
- **AND** the script continues using local refs and produces whatever sections it can

#### Scenario: Not inside a git repository

- **WHEN** the script is invoked outside any git work tree
- **THEN** it prints a one-line error to stderr
- **AND** exits with status 1

#### Scenario: jq missing on a GitLab repo

- **WHEN** `jq` is not on PATH and the origin is GitLab
- **THEN** the script exits with status 1
- **AND** prints an install hint directing the user to install `jq`
