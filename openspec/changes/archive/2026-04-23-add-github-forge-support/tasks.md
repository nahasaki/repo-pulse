## 1. CLI capability spike

- [x] 1.1 `glab auth status --hostname <h>` is supported but **exits 0 in both authed and unauthed cases**. Detection must parse stdout/stderr for "Logged in to <h>" (success) vs "has not been authenticated" (failure). Updated design understanding.
- [x] 1.2 Same finding for `gh auth status --hostname <h>` — exit 0 on both authed and unauthed hosts. Parse stdout for "Logged in to <h>" vs "not logged into any accounts". Detection code in Task 3 uses grep-based check, not exit code.
- [x] 1.3 `gh search prs --review-requested=@me --state=open --json number,title,author,createdAt,repository --limit 100` returns a JSON array. Empty array when no PRs match. Field shape: `{number, title, author: {login}, createdAt: "ISO", repository: {nameWithOwner}}`. Age is computed from `createdAt`.
- [x] 1.4 Correction discovered: `gh run list` does NOT expose `htmlUrl` — the field is `url`. Full verified `--json` list: `databaseId,displayTitle,status,conclusion,workflowName,createdAt,url`. `status` ∈ {queued, in_progress, completed}; `conclusion` ∈ {success, failure, cancelled, skipped, ...} when completed. Script uses `conclusion` if `status=="completed"`, else `status`.

## 2. Plugin manifest

- [x] 2.1 Bumped `.claude-plugin/plugin.json` `version` to `0.3.0`. No `userConfig` changes.

## 3. Detection block

- [x] 3.1 Added `extract_hostname` and forge-detection block: URL-first (`github.com`/`gitlab.com`), then local probes via `auth_hostname_matches` which greps stdout for "Logged in to <host>" (since exit codes are unreliable — see Task 1.1/1.2). Sets `FORGE` and `FORGE_HOSTNAME`.
- [x] 3.2 Removed `IS_GITLAB` entirely. All dispatch goes through `case "${FORGE}" in gitlab|github|*) …`.
- [x] 3.3 `HAS_GLAB` and `HAS_GH` are both defined, set only when the corresponding CLI is present AND `auth_hostname_matches` confirms auth for `FORGE_HOSTNAME`.

## 4. Install hints

- [x] 4.1 Added `emit_missing_cli_hint` function. Emits 6 `> note:` lines: reason, install header, brew/apt/dnf/other, final `auth login` (host-specific form when the hostname is not `github.com`/`gitlab.com`).
- [x] 4.2 Hint only called when `FORGE ∈ {gitlab, github}` AND CLI is missing or unauthed. `FORGE=unknown` path falls through silently. `jq` missing + known forge with CLI installed → fatal exit 1 with existing-shape install hint to stderr.

## 5. Section 3 — GitHub path

- [x] 5.1 Added `collect_section3_github`. Uses single `gh pr list -s all --json …` fetch. Check-rollup summarized to `success | failure | pending | mixed | —` via the spec's precedence rules.
- [x] 5.2 Renamed the existing body to `collect_section3_gitlab`; `collect_section3` is now a pure dispatcher.
- [x] 5.3 `ME_USERNAME` now populates from `gh api user --jq .login` when `HAS_GH=true`; mirrors the existing GitLab-identity path.

## 6. Section 5 — review inbox

- [x] 6.1 Added `collect_section5_github`. Format: `#<num> **<title>** — <author>, age: <N days> [<owner>/<repo>]`. The repository suffix is added because cross-repo search means entries may come from different projects (unlike GitLab section 5 which scopes to the authenticated user's project list).
- [x] 6.2 `collect_section5` renamed/split; GitLab body identical to v0.2.0.

## 7. Section 6 — CI status (adaptive label)

- [x] 7.1 Added `collect_section6_github`. Uses `--json …,url` (not `htmlUrl` — that field doesn't exist per spike 1.4). Output line: `- <workflow-name> #<databaseId> <status-or-conclusion> — YYYY-MM-DD HH:MM (<url>)`. Verified against `cli/cli` live: `- Triage Scheduled Tasks #24842141460 success — 2026-04-23 14:56 (…)`.
- [x] 7.2 GitLab `collect_section6_gitlab` body unchanged byte-for-byte.

## 8. Skill metadata

- [x] 8.1 `allowed-tools` now includes `Bash(gh:*)` alongside `Bash(glab:*)`.
- [x] 8.2 Body rewritten: notes GitHub/GitLab/unknown forge model, explicitly tells Claude to surface (not re-type) the install hints the script already emits. "Open — mine" / "diff for PR #456" mentioned as follow-up examples.

## 9. Documentation sweep

 - [x] 9.1 SPEC.md §Scope now says "GitHub and GitLab supported" with probe detection for GHE / self-hosted GitLab. Unknown forges explicit.
- [x] 9.2 SPEC.md §3/§5/§6 rewritten forge-aware with command variants + prefix/label rules.
- [x] 9.3 SPEC.md §Error Handling table expanded: 6 forge-specific rows (install missing / unauthed / unknown) + existing rows.
- [x] 9.4 README.md positioning updated: "Works out of the box on GitHub and GitLab", forge auto-detection narrative. Version bumped to 0.3.0 in the mention.
- [x] 9.5 Grep-swept `gitlab-first`, `IS_GITLAB`, `non-gitlab`; only remaining mentions of "GitHub" and "GitLab" are in contexts describing both (intended).

## 10. Acceptance

- [x] 10.1 GitLab regression pass on `promin/funnels-builder`. With matched identity (`CLAUDE_PLUGIN_OPTION_EXTRA_EMAILS='["m.tantsyura@promin-apps.com"]'`), section structure is byte-identical to v0.2.0; content differences reflect real commits arriving in the 6h between runs and are not regressions. All six sections produced, `!<iid>` prefix intact, GitLab §6 format unchanged.
- [x] 10.2 GitHub positive path validated on a shallow clone of `cli/cli` (highly active repo with PRs and workflow runs). Output: 6-section report including 22 merges, 23 open PRs, 16 merged PRs in a 3-day window, and `- Triage Scheduled Tasks #24842141460 success — 2026-04-23 14:56 (…)` in §6. All entries use `#<number>` prefix; `checks: <rollup>` column populates with `success | failure | pending | mixed | —`.
- [x] 10.3 Temporarily removed `/opt/homebrew/bin` from PATH while in the `cli-test` repo. Output led with the multi-line install hint (6 `> note:` lines covering macOS/Debian/Fedora/other + `gh auth login`); §3/§5/§6 omitted; §1/§2/§4 present; exit 0.
- [x] 10.4 Created `/tmp/wn-unknown` with `git remote add origin git@codeberg.org:nobody/nothing.git`. Script output contains only the two non-forge `> note:` lines (offline + missing default ref); explicit grep confirms absence of `origin is on / Install: / brew install / auth login`. PASS: `FORGE=unknown` runs silently.
- [ ] 10.5 **PENDING USER VALIDATION.** No GHE or self-hosted GitLab instance accessible from this machine. Probe-fallback code paths are exercised by spikes 1.1/1.2 (the `auth_hostname_matches` helper's grep-based check is identical regardless of hostname). Full end-to-end on a GHE repo will confirm when such access is available.
- [ ] 10.6 **PENDING USER VALIDATION.** Requires interactive Claude Code session. Steps: `cd` into a GitHub repo, run `/repo-pulse:whats-new`, then ask "show me the diff for PR #<n>". Expected: `gh` command runs without a permission prompt because `Bash(gh:*)` is now in `allowed-tools` (Task 8.1).
