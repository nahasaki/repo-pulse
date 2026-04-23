## ADDED Requirements

### Requirement: Forge detection

The system SHALL detect the hosting forge of the current repository's `origin` remote and set an internal `FORGE` value to one of `github`, `gitlab`, or `unknown`. Detection precedence:

1. **URL match (fast path).** If the origin URL contains the literal substring `github.com`, set `FORGE=github`. If it contains `gitlab.com`, set `FORGE=gitlab`.
2. **Local CLI probe (self-hosted fallback).** Extract the domain from the origin URL (handling `git@host:owner/repo.git`, `https://host/owner/repo`, and `git://host/...`). Try `gh auth status --hostname <domain>` — if it exits 0, set `FORGE=github`. Otherwise try `glab auth status --hostname <domain>` (falling back to `glab auth status 2>&1` scanning for the domain if the `--hostname` flag is unsupported) — if it succeeds, set `FORGE=gitlab`.
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
- **AND** `gh auth status --hostname github.acme.corp` exits 0
- **THEN** `FORGE = github`

#### Scenario: Self-hosted GitLab via probe

- **WHEN** origin URL is `https://gitlab.internal/group/project.git`
- **AND** `gh auth status --hostname gitlab.internal` exits non-zero
- **AND** `glab auth status --hostname gitlab.internal` exits 0
- **THEN** `FORGE = gitlab`

#### Scenario: Unknown forge

- **WHEN** origin URL is `https://codeberg.org/user/repo.git`
- **AND** neither `gh` nor `glab` report the domain as authed
- **THEN** `FORGE = unknown`
- **AND** the script produces git-only sections (1, 2, 4) with NO install hint in the output

## MODIFIED Requirements

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
