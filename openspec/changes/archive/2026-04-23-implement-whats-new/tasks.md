## 1. Plugin scaffolding

- [x] 1.1 Create `.claude-plugin/plugin.json` with `name`, `version` (`0.1.0`), `description`, and `author` per `CLAUDE.md` §"Plugin manifest".
- [x] 1.2 Create `skills/whats-new/config.sh` as a committed template: `MY_EMAILS=()` and `DEFAULT_SINCE="7 days ago"`. No personal data. Confirm `.gitignore` already excludes `**/config.local.sh`.

## 2. Script skeleton

- [x] 2.1 Create `skills/whats-new/scripts/whats-new.sh` with `#!/usr/bin/env bash`, `set -euo pipefail`, config sourcing (`config.sh` then `config.local.sh` if present), `--since=<period>` argument parsing, and a placeholder body that prints a stub header — so the script is end-to-end runnable before real logic lands.
- [x] 2.2 Make the script executable: `chmod +x skills/whats-new/scripts/whats-new.sh`. Commit the executable bit.

## 3. Preflight and window resolution

- [x] 3.1 Implement preflight checks: in-a-git-work-tree (fatal), origin-is-GitLab probe, `glab auth status` probe, `jq` presence. Feed non-fatal failures to the `> note:` warning channel; fatal cases exit 1 per `specs/whats-new/spec.md` §"Preflight and graceful degradation".
- [x] 3.2 Implement `git fetch --all --prune --quiet` with soft failure (warn on non-zero, continue against stale refs).
- [x] 3.3 Implement default-branch detection via `git symbolic-ref refs/remotes/origin/HEAD`, with `main` as the last-resort fallback. No config override.
- [x] 3.4 Implement window resolution: passthrough of `--since`; else smart default from the most recent commit matching `MY_EMAILS` by committer date; else `DEFAULT_SINCE` fallback. Emit the correct `<reason>` string (`from your last commit on <ISO date>`, `--since=<value>`, or `DEFAULT_SINCE fallback (<value>)`).

## 4. Section collectors

- [x] 4.1 Section 1 "Merged to default": `git log origin/<default> --since=<T> --no-merges`, post-filter against `MY_EMAILS` to exclude the user's own commits. Format per `SPEC.md` §Output Format.
- [x] 4.2 Section 2 "New / updated remote branches": `git for-each-ref refs/remotes/origin/` sorted by committerdate; filter to window, exclude default, exclude branches whose every in-window commit is by the user; compute commits-ahead-of-default.
- [x] 4.3 Section 3 "Merge requests": probe `glab mr list --updated-after` support; either use it or fetch full JSON via `glab mr list -F json` and filter by `updated_at`. Split into three subsections (Open — others, Merged this period, Open — mine) per spec.
- [x] 4.4 Section 4 "My activity": `git log --all --since=<T> --author=<regex>` where the regex is an OR-join of `MY_EMAILS`. Group output by branch then by date.
- [x] 4.5 Section 5 "MRs awaiting my review": `glab mr list --reviewer=@me` (no time filter); format each line with MR age in days.
- [x] 4.6 Section 6 "CI on default": query the last pipeline on `origin/<default>` and emit one line with id, status, created_at (local time), and web URL.

## 5. Assembly and output

- [x] 5.1 Run sections in parallel: each section writes stdout to its own tempfile and stderr to a per-job capture; `wait` on all; concatenate in fixed order. Tempfiles are cleaned up via a `trap EXIT`.
- [x] 5.2 Emit output header (`# What's new in <repo-slug>`, `Window: <ISO start> → <ISO end> (<reason>)`) and aggregate all `> note:` warnings at the top of the output.
- [x] 5.3 Empty-section handling: omit sections with zero items; if every section is empty, print a single line `Nothing new since <ISO start>` and exit 0.

## 6. Skill definition

- [x] 6.1 Create `skills/whats-new/SKILL.md` per `SPEC.md` §"SKILL.md Sketch": frontmatter with `name`, `description` (including catch-up trigger phrases so auto-invocation works), `argument-hint`, and `allowed-tools` scoped to the script plus `Bash(git:*)` and `Bash(glab:*)` for follow-ups. Body instructs Claude to run the script, prepend a 1–3 bullet TL;DR, and answer follow-ups conversationally.

## 7. Manual acceptance

- [x] 7.1 Acceptance 1 — `promin/funnels-builder`: launch Claude with `--plugin-dir`, run `/repo-pulse:whats-new`, confirm all six sections populate and the window header reports the user's last commit. Capture output in the commit body.
- [x] 7.2 Acceptance 2 — a GitHub repo: confirm the non-GitLab `> note:` warning appears and only sections 1, 2, and 4 are produced. Exit status must be 0.
- [x] 7.3 Acceptance 3 — empty-window case: run twice in quick succession against any repo; confirm the second run prints only `Nothing new since <T>`.

## 8. Marketplace packaging

- [x] 8.1 Create `.claude-plugin/marketplace.json` declaring this repo as a single-plugin marketplace per `CLAUDE.md` §"Install as a marketplace of one". Verify end-to-end install by running `/plugin marketplace add` + `/plugin install repo-pulse@repo-pulse` in a fresh Claude Code session.
