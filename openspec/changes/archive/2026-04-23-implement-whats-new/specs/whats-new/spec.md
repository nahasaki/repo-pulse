## ADDED Requirements

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

The system SHALL determine the window start by the following precedence:

1. If `--since` is provided, use its value.
2. Else, find the most recent commit across all refs whose author email matches any entry in `MY_EMAILS`, and use that commit's **committer date** as the window start.
3. Else, fall back to `DEFAULT_SINCE` from config.

All time comparisons throughout the system SHALL use committer date, never author date.

#### Scenario: Smart default succeeds

- **WHEN** at least one commit in the repo has an author email matching `MY_EMAILS`
- **THEN** the window start equals that commit's committer date
- **AND** the output header's `<reason>` reads `from your last commit on <ISO date>`

#### Scenario: Smart default falls back

- **WHEN** no commit matches `MY_EMAILS`, or `MY_EMAILS` is empty
- **THEN** the window start equals `now − DEFAULT_SINCE`
- **AND** the output header's `<reason>` reads `DEFAULT_SINCE fallback (<value>)`

### Requirement: Six-section markdown output

The system SHALL produce plain markdown to stdout in this fixed section order, omitting any section that is empty:

1. **Merged to default** — commits reachable from `origin/<default>` within the window, authored by someone other than the user, excluding merge commits.
2. **New / updated remote branches** — non-default remote branches whose last commit is within the window, excluding branches whose every in-window commit is by the user. Shows name, last committer name, last commit time, and commits-ahead count relative to the default branch.
3. **Merge requests** — three subsections: "Open — others" (authored by someone else, still open), "Merged this period" (any author, merged in window), "Open — mine" (authored by the user, still open). Each entry: `!<iid> <title> — <author>, <source> → <target>, CI: <status>`.
4. **My activity** — commits across all refs within the window authored by any address in `MY_EMAILS`, grouped by branch then by date.
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

### Requirement: Configuration via template plus local override

The system SHALL source `skills/whats-new/config.sh` first, then `skills/whats-new/config.local.sh` if present (which overrides any values). `config.sh` is a committed template with `MY_EMAILS=()` and `DEFAULT_SINCE="7 days ago"`. `config.local.sh` is gitignored and contains personal data. The committed template MUST NOT contain personal data.

#### Scenario: Local overrides apply

- **WHEN** `config.sh` defines `MY_EMAILS=()` and `config.local.sh` defines `MY_EMAILS=("you@example.com")`
- **THEN** the effective value of `MY_EMAILS` used by the script is `("you@example.com")`

#### Scenario: No local config present

- **WHEN** only `config.sh` exists and `MY_EMAILS` is empty
- **THEN** the script runs without error
- **AND** the window resolves via the `DEFAULT_SINCE` fallback
- **AND** section 4 ("My activity") is empty

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
