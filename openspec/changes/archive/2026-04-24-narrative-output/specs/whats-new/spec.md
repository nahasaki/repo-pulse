# whats-new — delta for narrative-output

Pivots the user-visible output from six structured sections to 1–4
prose paragraphs. The shell script's output format is retained as
internal scratch data the skill parses. Themes is retired and
absorbed into the new Shipped paragraph. New requirements cover
collision detection and PR/branch linkification.

## ADDED Requirements

### Requirement: Narrative prose output

The skill SHALL compose the user-visible output as prose paragraphs
in a fixed role order, preceded by a two-line header and skipping
any role whose source data is empty:

```
# What's new in <repo-slug>

Window: <ISO start> → <ISO end> (<reason>)

<Shipped paragraph, optional>

<In flight paragraph, optional>

<Needs you paragraph, optional>

<You paragraph, optional>
```

| Role | Source | Include when |
|------|--------|--------------|
| **Shipped** | §1 Merged + §3 Merged-this-period | Any merged work in-window |
| **In flight** | §2 New/updated branches + §3 Open (others) + collision flags | Any open PRs or new branches |
| **Needs you** | §5 Awaiting my review + §6 CI (failures or mine-PRs with stalled checks) | Any review-due or CI-red items |
| **You** | §4 My activity | User has commits in-window |

Each paragraph SHALL be written as flowing prose, not a bullet list.
No numeric totals appear in the prose; PR and branch references
appear as markdown links per the PR and branch link rendering
requirement. Commit SHAs MAY be included when specifically calling
out a single commit, but are not required.

Empty paragraphs SHALL NOT render a placeholder or divider — they
are simply omitted. If every role is empty, the skill SHALL emit
the pre-existing `Nothing new since <ISO>` one-liner instead of a
prose paragraph.

#### Scenario: Busy repo with all four roles populated

- **WHEN** the window has merged work, new branches, open PRs, PRs
  awaiting the user's review, and user activity
- **THEN** the output contains 4 paragraphs in order:
  Shipped → In flight → Needs you → You
- **AND** each paragraph is separated from the next by a blank line
- **AND** no `## Merged to …`, `## Merge requests`, or other §-style
  headings appear in the output

#### Scenario: Quiet repo with only user activity

- **WHEN** the window contains only 3 commits by the user on `main`
  and nothing else (no colleagues' work, no open PRs, no reviews
  pending, CI green)
- **THEN** the output contains only the You paragraph after the
  header
- **AND** the Shipped, In flight, and Needs you paragraphs are
  omitted entirely

#### Scenario: Empty window preserves single-line summary

- **WHEN** every source section is empty (nothing merged, no
  branches, no PRs, no reviews, no CI runs, no user commits)
- **THEN** the skill emits exactly one line: `Nothing new since <ISO start>`
- **AND** no header or paragraphs are rendered

#### Scenario: Header is always present when non-empty

- **WHEN** the output contains at least one paragraph
- **THEN** the first two lines are the `# What's new in …` heading
  and the `Window: …` line
- **AND** a blank line separates the header from the first paragraph

### Requirement: Collision detection for in-flight work

The skill SHALL cross-reference other contributors' active work with
the user's work to flag likely collisions in the In flight paragraph.

**Inputs:**

- `MY_BRANCHES` = union of §4 "My activity" branch names, the
  currently checked-out branch, and `git branch --list` output.
- `THEIRS_BRANCHES` = source branches of §3 Open (others) PRs ∪ §2
  new/updated remote branches.

**Collision triggers** (any one suffices):

1. **Name overlap**: after lowercasing, an other-branch name shares
   ≥ 3 consecutive characters or a path segment with any of
   MY_BRANCHES, and the shared substring is not a common word like
   `main`, `master`, `develop`, or `fix`.
2. **Path overlap with conventional-commit match**: if the user's
   most recent commit on their WIP branch touches a top-level path
   `P`, and an open PR has `P` as a prefix of any file in its
   changed-files list AND the PR's conventional-commit-type matches
   the user's recent work (both `feat:` or both `fix:`), trigger.

When triggered, the skill SHALL emit a heads-up phrase inside the In
flight paragraph, e.g., *"Heads-up: Sam's open [#13266] touches the
same skill-install area as your branch `fix-skill-install`."*

When no collision triggers, the In flight paragraph describes
others' work in neutral prose without a heads-up phrase.

False positives are acceptable (user is the judge); false negatives
are the failure mode to avoid.

#### Scenario: Name overlap triggers heads-up

- **WHEN** the user has a local branch `user/feat-auth-login` and
  an open PR from another contributor uses source branch
  `user/feat-auth-refresh`
- **THEN** the In flight paragraph includes a heads-up calling out
  the overlapping work by name, with the PR linked

#### Scenario: Path overlap triggers heads-up

- **WHEN** the user's most recent commit on their WIP branch touches
  `pkg/cmd/telemetry/` and an open PR's changed-files list includes
  `pkg/cmd/telemetry/host.go` AND both are `feat:`-prefixed
- **THEN** the In flight paragraph includes a heads-up that the
  two efforts are working in the same area

#### Scenario: No overlap produces neutral prose

- **WHEN** open PRs and new branches are unrelated to the user's
  current work (no name or path overlap)
- **THEN** the In flight paragraph summarizes others' work without
  any "heads-up" phrasing

#### Scenario: Multiple collisions all flagged

- **WHEN** two open PRs both overlap with the user's current
  branch — one by name, one by path
- **THEN** the In flight paragraph flags both collisions
- **AND** each flagged PR is linked with a markdown link

### Requirement: PR and branch link rendering

References to PRs, MRs, and branches inside the narrative SHALL be
rendered as GitHub-Flavored Markdown links clickable in Claude Code's
terminal renderer. The skill SHALL NOT emit OSC 8 escape sequences or
raw terminal-control codes — only standard markdown.

URL construction:

| Reference | GitHub URL | GitLab URL |
|-----------|------------|------------|
| PR / MR | `[#<N>](https://<host>/<owner>/<repo>/pull/<N>)` | `[!<iid>](https://<host>/<owner>/<repo>/-/merge_requests/<iid>)` |
| Branch | `` [`<branch>`](https://<host>/<owner>/<repo>/tree/<branch>) `` | `` [`<branch>`](https://<host>/<owner>/<repo>/-/tree/<branch>) `` |
| Commit (if cited) | `` [`<sha>`](https://<host>/<owner>/<repo>/commit/<sha>) `` | `` [`<sha>`](https://<host>/<owner>/<repo>/-/commit/<sha>) `` |

The skill SHALL derive `<host>`, `<owner>`, and `<repo>` from `git
remote get-url origin`, handling both HTTPS and SSH remotes and
stripping any trailing `.git` suffix.

On unknown-forge origins (FORGE = unknown), the skill SHALL emit
plain text without links: `#<N>`, `` `<branch>` ``, `` `<sha>` ``. The
information stays present; only the link wrapper is omitted.

#### Scenario: GitHub PR reference is linked

- **WHEN** the origin is `https://github.com/cli/cli.git` and PR
  number 13272 is referenced
- **THEN** the rendered text is `[#13272](https://github.com/cli/cli/pull/13272)`

#### Scenario: GitLab MR reference uses the `-/merge_requests/` path

- **WHEN** the origin is `https://gitlab.com/owner/proj.git` and MR
  iid 5678 is referenced
- **THEN** the rendered text is `[!5678](https://gitlab.com/owner/proj/-/merge_requests/5678)`

#### Scenario: Branch name becomes a clickable link with backticks preserved

- **WHEN** a GitHub repo has a branch `feat/auth-refresh`
- **THEN** the rendered text is `` [`feat/auth-refresh`](https://github.com/<owner>/<repo>/tree/feat/auth-refresh) ``
- **AND** the backticks are inside the link-text brackets so the
  rendered link displays in code-formatted style

#### Scenario: Unknown forge produces plain text

- **WHEN** the origin is `https://codeberg.org/user/repo.git` and
  no forge CLI reports the host as authed
- **THEN** PR references appear as plain `#<N>` with no markdown
  link wrapper
- **AND** branch references appear as `` `<branch>` `` with no link

#### Scenario: SSH origin URL is translated correctly

- **WHEN** the origin is `git@github.com:cli/cli.git` and PR 42 is
  referenced
- **THEN** the URL inside the markdown link is
  `https://github.com/cli/cli/pull/42`
- **AND** the `.git` suffix and SSH prefix are stripped

## MODIFIED Requirements

### Requirement: Six-section markdown output

The shell script `whats-new.sh` SHALL produce plain markdown to stdout
in this fixed section order, omitting any section that is empty.
This output is **internal scratch data** for the skill's narrative
composition layer; it is NOT the user-visible output. Users who run
the script directly still see these six sections, which is useful
for debugging the underlying data collection.

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

If every section is empty, the script SHALL print a single-line summary `Nothing new since <ISO start>` and nothing else. The skill SHALL pass this line through unchanged when it appears.

**The skill consumes this output** and emits prose per the Narrative prose output requirement. The skill MUST NOT show the raw section markdown to the user; it only uses the structure to extract facts.

#### Scenario: All sections empty

- **WHEN** the window contains no colleague activity, no user commits, no MR updates, and no new pipelines
- **THEN** the script prints a single line: `Nothing new since <ISO start>`
- **AND** the skill passes that line through as the user-visible output

#### Scenario: Mixed sections parsed by the skill

- **WHEN** sections 1 and 4 have data but sections 2, 3, 5, and 6 are empty
- **THEN** the script's output contains the "Merged to default" and "My activity" sections, in that order
- **AND** the skill parses those two sections and emits the Shipped and You paragraphs

#### Scenario: GitHub repo with PRs

- **WHEN** `FORGE = github` and the repo has 2 open PRs by others, 3 merged in window, 1 open by the user
- **THEN** the script's section 3 renders three subsections, each with `#<number>` prefixed entries
- **AND** the skill reads those entries to compose the Shipped (merged PRs) and In flight (open PRs) paragraphs

#### Scenario: Cross-forge visual consistency (script layer)

- **WHEN** the same report structure is produced on a GitLab repo and a GitHub repo (same non-zero counts per section)
- **THEN** the script's section headers and order are identical
- **BUT** GitLab entries use `!` prefix and GitHub entries use `#` prefix
- **AND** section 6 on GitHub includes the workflow name in the line; on GitLab it does not

#### Scenario: Adaptive §6 label

- **WHEN** `FORGE = github` and the latest run on the default branch is named "Build and Test" with id 987 and status "success"
- **THEN** the script's section 6 emits: `- Build and Test #987 success — <datetime> (<url>)`

#### Scenario: GitLab §6 unchanged

- **WHEN** `FORGE = gitlab` and the latest pipeline id is 2457640709 status "success"
- **THEN** the script's section 6 emits: `- #2457640709 success — <datetime> (<url>)`
- **AND** the format is byte-for-byte identical to v0.2.0

### Requirement: Subagent dispatch rules (parallel mode)

When `parallel` mode is selected, the skill SHALL spawn one subagent per cluster via the `Task` tool with these rules:

- Maximum 8 concurrent subagents. If more clusters exist, process in batches of 8.
- Each subagent receives:
  - A fixed prompt: "Here are N commits by `<author>` with `<type>:` prefix, all touching `<path-root>`. Run `git show <sha>` for each and describe in one or two sentences what these commits collectively accomplished, suitable as a clause inside a longer paragraph. Focus on what the user would want to know — the concrete change, not generic context. Reply with exactly one or two sentences, no preamble, no markdown formatting, no bullets, no emoji."
  - Scoped tools: `Bash(git:*)` only. No `gh`, no `glab`, no `Read`.
  - A context cap instruction: "Do not read more than 30 lines of each diff; truncate large file blocks."
  - A `model` parameter taken from the validated `summary_model` userConfig value (`haiku`, `sonnet`, or `opus`). When the value is `inherit`, the `model` parameter SHALL be omitted so the subagent follows the host session.
- Subagents that error or time out MUST NOT fail the whole skill. The skill SHALL discard the failed cluster's summary (the cluster's commits still contribute to the Shipped paragraph at title-level only).
- If a non-trivial fraction (≥ 25%) of subagents failed, the skill SHALL emit a `> note:` indicating degraded themes output.

The subagent returns a clause (one or two sentences). The host session stitches clauses into the Shipped paragraph with connective phrasing — subagents MUST NOT produce bullets or section headings.

#### Scenario: 12 clusters processed in two batches

- **WHEN** `parallel` mode is selected and clustering produced 12 clusters
- **THEN** the skill spawns subagents in batches of 8
- **AND** the first batch has 8 subagents, the second has 4
- **AND** all 12 clause candidates are collected

#### Scenario: one subagent fails, others succeed

- **WHEN** `parallel` mode spawns 5 subagents and 1 returns an error
- **THEN** the Shipped paragraph is composed from 4 clauses
- **AND** no `> note:` is emitted (1/5 < 25%)

#### Scenario: many subagents fail — degraded note emitted

- **WHEN** `parallel` mode spawns 8 subagents and 3 return errors
- **THEN** the Shipped paragraph composes from 5 clauses
- **AND** a `> note: themes partially degraded: 3 of 8 clusters failed to summarize` is emitted

#### Scenario: dispatch uses configured summary_model

- **WHEN** `summary_model` resolves to `haiku` and `parallel` mode spawns 4 subagents
- **THEN** each of the 4 `Task` invocations includes `model: "haiku"`
- **AND** subagents run on Haiku even if the host session is on Opus or Sonnet

#### Scenario: dispatch uses inherit when configured

- **WHEN** `summary_model` resolves to `inherit` and `parallel` mode spawns 3 subagents
- **THEN** each of the 3 `Task` invocations omits the `model` parameter
- **AND** subagents inherit the host session's model

#### Scenario: subagent returns a clause, not a bullet

- **WHEN** a subagent is dispatched for a cluster of 4 telemetry commits
- **THEN** the returned text is one or two sentences of prose (e.g., "William Martin rolled out a `telemetry` command with error recording and host categorization, enabled without an env var.")
- **AND** the returned text contains no leading dash, no markdown formatting, and no section heading

### Requirement: Configuration — summary_mode

The system SHALL expose a `summary_mode` userConfig key in `.claude-plugin/plugin.json` with enum values `auto`, `off`, and `always`. Default value is `auto`.

The option SHALL be exposed to the script as `CLAUDE_PLUGIN_OPTION_SUMMARY_MODE` and consumed by the skill via the same mechanism.

Semantics in the narrative-output era:

- `auto`: the skill applies the threshold logic (serial vs parallel vs skip) to decide how to read diffs for the Shipped paragraph. Other paragraphs (In flight, Needs you, You) always render; their content does not need diff reads.
- `off`: the skill SKIPS diff reads entirely. The Shipped paragraph is composed from commit subjects and PR titles only — prose quality degrades but the paragraph still renders (degraded prose is still prose; empty prose is not an option). This is the pre-0.4.0 equivalent of "no themes analysis", translated to the new output shape.
- `always`: the skill forces the parallel subagent path for diff reads, regardless of commit volume.

#### Scenario: default is auto

- **WHEN** a user installs the plugin fresh without setting the option
- **THEN** `summary_mode` resolves to `auto`
- **AND** the skill applies the threshold logic for the Shipped paragraph

#### Scenario: user sets off — Shipped paragraph degrades

- **WHEN** the user sets `summary_mode` to `off` via the plugin config UI or by editing `~/.claude/settings.json`
- **THEN** the skill does not read any diffs
- **AND** the Shipped paragraph is composed from commit subjects and PR titles only
- **AND** the In flight, Needs you, and You paragraphs render normally

#### Scenario: invalid value falls back to auto

- **WHEN** the env var `CLAUDE_PLUGIN_OPTION_SUMMARY_MODE` is set to something outside `{auto, off, always}`
- **THEN** the skill treats the value as `auto` and optionally emits a `> note:` mentioning the unknown value

## REMOVED Requirements

### Requirement: Themes section above §1

**Reason:** Superseded by the Narrative prose output requirement. The
"themes" concept — semantically clustered summaries of merged work —
is absorbed into the new Shipped paragraph, where subagents produce
clauses rather than standalone bullets and the host session stitches
them into prose.

**Migration:** No user action needed. The existing `summary_mode`,
`summary_max_commits`, and `summary_model` userConfig keys retain
their semantics (with `summary_mode: off` degrading prose rather
than suppressing a section). Any user invocation of `/repo-pulse:whats-new`
will simply see prose instead of the themes-plus-sections layout.
