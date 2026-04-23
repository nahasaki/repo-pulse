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

1. **Merged to default** — unchanged.
2. **New / updated remote branches** — unchanged.
3. **Merge requests / Pull requests** — forge-aware:
   - On GitLab: three subsections (Open — others, Merged this period, Open — mine) using `glab`. Each entry: `!<iid> <title> — <author>, <source> → <target>, CI: <status>`.
   - On GitHub: same three subsections using `gh`. Each entry: `#<number> <title> — <author>, <source> → <target>, checks: <status>`.
   - On unknown forge: omitted entirely.
4. **My activity** — unchanged (identity-driven, forge-agnostic).
5. **MRs/PRs awaiting my review** — forge-aware:
   - On GitLab: `glab mr list --reviewer=@me`. Entries: `!<iid> <title> — <author>, age: <N days>`.
   - On GitHub: `gh search prs --review-requested=@me --state=open --json …`. Entries: `#<number> <title> — <author>, age: <N days>`.
   - On unknown forge: omitted.
6. **CI on default** — forge-aware:
   - On GitLab: `- #<pipeline-id> <status> — YYYY-MM-DD HH:MM (<url>)`.
   - On GitHub: `- <workflow-name> #<run-id> <status> — YYYY-MM-DD HH:MM (<url>)`.
   - On unknown forge: omitted.

Section prefix characters (`!` vs `#`) SHALL match the forge's native convention. Normalization across forges is forbidden.

If every section is empty, the system SHALL print a single-line summary `Nothing new since <ISO start>` and nothing else.

**Downstream Claude TL;DR logic depends on this output shape.** Any future change to the section order or the set of section headers MUST explicitly call that out in its proposal.

#### Scenario: All sections empty

- **WHEN** the window contains no colleague activity, no user commits, no MR updates, and no new pipelines
- **THEN** the script prints a single line: `Nothing new since <ISO start>`

#### Scenario: Mixed sections

- **WHEN** sections 1 and 4 have data but sections 2, 3, 5, and 6 are empty
- **THEN** the output includes the "Merged to default" and "My activity" sections, in that order
- **AND** no empty section headers appear

#### Scenario: GitHub repo with PRs

- **WHEN** `FORGE = github` and the repo has 2 open PRs by others, 3 merged in window, 1 open by the user
- **THEN** section 3 renders three subsections, each with `#<number>` prefixed entries
- **AND** the "checks" column reflects the PR's combined check status

#### Scenario: Cross-forge visual consistency

- **WHEN** the same report structure is produced on a GitLab repo and a GitHub repo (same non-zero counts per section)
- **THEN** the section headers and order are identical
- **BUT** GitLab entries use `!` prefix and GitHub entries use `#` prefix
- **AND** section 6 on GitHub includes the workflow name in the line; on GitLab it does not

#### Scenario: Adaptive §6 label

- **WHEN** `FORGE = github` and the latest run on the default branch is named "Build and Test" with id 987 and status "success"
- **THEN** section 6 emits: `- Build and Test #987 success — <datetime> (<url>)`

#### Scenario: GitLab §6 unchanged

- **WHEN** `FORGE = gitlab` and the latest pipeline id is 2457640709 status "success"
- **THEN** section 6 emits: `- #2457640709 success — <datetime> (<url>)`
- **AND** the format is byte-for-byte identical to v0.2.0

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

The system SHALL handle preflight failures and missing dependencies as follows:

| Condition | Behavior |
|---|---|
| Not in a git work tree | One-line message to stderr, exit 1 |
| `git fetch` fails (offline) | Print `> note:` warning; continue against stale refs |
| `FORGE=github` and `gh` not installed | Print install hint (see below); run git-only sections (1, 2, 4) |
| `FORGE=github` and `gh` installed but not authed for the hostname | Print hint suggesting `gh auth login --hostname <host>`; run git-only sections |
| `FORGE=gitlab` and `glab` not installed | Print install hint (see below); run git-only sections |
| `FORGE=gitlab` and `glab` installed but not authed | Print hint suggesting `glab auth login`; run git-only sections |
| `FORGE=unknown` | Run git-only sections silently — no forge-related hint |
| `jq` missing and `FORGE ∈ {github, gitlab}` with the respective CLI present | Exit 1 with a jq install hint |
| `jq` missing and `FORGE=unknown` | Warn, skip CLI-dependent sections (same behavior as missing CLI) |

Install hints SHALL be multi-line `> note:` blocks with platform-specific commands. Example for GitHub:

```
> note: origin is on GitHub but `gh` is not installed. §3/§5/§6 will be empty.
> Install:
>   macOS:    brew install gh
>   Debian:   sudo apt install gh
>   Fedora:   sudo dnf install gh
>   other:    https://cli.github.com/
> Then run:  gh auth login
```

All non-fatal warnings SHALL be emitted as lines prefixed with `> note:` at the top of the output so Claude surfaces them to the user without treating them as data.

#### Scenario: GitHub repo, gh missing

- **WHEN** `FORGE = github` and `gh` is not on PATH
- **THEN** a multi-line `> note:` install hint appears at the top of the output, naming `brew install gh` (macOS), `sudo apt install gh` (Debian), `sudo dnf install gh` (Fedora), and a final `gh auth login` instruction
- **AND** only sections 1, 2, and 4 are produced
- **AND** the exit status is 0

#### Scenario: GitLab repo, glab missing

- **WHEN** `FORGE = gitlab` and `glab` is not on PATH
- **THEN** an analogous `> note:` hint appears naming `brew install glab`, the Debian package URL, `sudo dnf install glab`, and `glab auth login`
- **AND** only sections 1, 2, and 4 are produced
- **AND** the exit status is 0

#### Scenario: Unknown forge, silent

- **WHEN** `FORGE = unknown`
- **THEN** the output contains NO install hint naming `gh`, `glab`, or any forge CLI
- **AND** only sections 1, 2, and 4 are produced

#### Scenario: GHE with gh present but unauthed for hostname

- **WHEN** `FORGE = github` via URL match AND `gh auth status --hostname <host>` exits non-zero
- **THEN** the `> note:` hint specifically suggests `gh auth login --hostname <host>` with the detected hostname
- **AND** only sections 1, 2, and 4 are produced

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

### Requirement: Forge detection

The system SHALL detect the hosting forge of the current repository's `origin` remote and set an internal `FORGE` value to one of `github`, `gitlab`, or `unknown`. Detection precedence:

1. **URL match (fast path).** If the origin URL contains the literal substring `github.com`, set `FORGE=github`. If it contains `gitlab.com`, set `FORGE=gitlab`.
2. **Local CLI probe (self-hosted fallback).** Extract the domain from the origin URL (handling `git@host:owner/repo.git`, `https://host/owner/repo`, and `git://host/...`). Try `gh auth status --hostname <domain>` — if the output contains `Logged in to <domain>`, set `FORGE=github`. Otherwise try `glab auth status --hostname <domain>` with the same grep-based check — if it matches, set `FORGE=gitlab`. (Both CLIs exit 0 regardless of auth state, so the exit code is not a reliable signal.)
3. **Default.** If all of the above fail, set `FORGE=unknown`.

Probes MUST NOT make network calls — they are local config checks only.

#### Scenario: GitHub by URL

- **WHEN** origin URL is `https://github.com/owner/repo.git`
- **THEN** `FORGE = github`
- **AND** no CLI probe runs

#### Scenario: GitLab by URL

- **WHEN** origin URL is `git@gitlab.com:group/project.git`
- **THEN** `FORGE = gitlab`
- **AND** no CLI probe runs

#### Scenario: GitHub Enterprise via probe

- **WHEN** origin URL is `git@github.acme.corp:team/app.git`
- **AND** `gh auth status --hostname github.acme.corp` output contains `Logged in to github.acme.corp`
- **THEN** `FORGE = github`

#### Scenario: Self-hosted GitLab via probe

- **WHEN** origin URL is `https://gitlab.internal/group/project.git`
- **AND** `gh auth status --hostname gitlab.internal` does not report the host as authed
- **AND** `glab auth status --hostname gitlab.internal` output contains `Logged in to gitlab.internal`
- **THEN** `FORGE = gitlab`

#### Scenario: Unknown forge

- **WHEN** origin URL is `https://codeberg.org/user/repo.git`
- **AND** neither `gh` nor `glab` report the domain as authed
- **THEN** `FORGE = unknown`
- **AND** the script produces git-only sections (1, 2, 4) with NO install hint in the output
