---
name: whats-new
description: Summarize what changed in the current git repository since the user was last active. Shows merged commits on the default branch, new or updated remote branches, open and merged MRs on GitLab, the user's own recent commits, MRs awaiting review, and CI status on the default branch. Use when the user asks "what's new", "catch me up", "what did the team do", or returns to a repo after an absence.
argument-hint: [--since=<period>]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/whats-new/scripts/whats-new.sh:*), Bash(git:*), Bash(glab:*), Bash(gh:*)
---

# whats-new

Summarize activity in the current git repository, then prepend a short TL;DR
before the script's markdown output.

## Steps

1. Run the summary script. Pass through any `--since=<period>` argument the
   user provided; if they did not, run it with no arguments so the smart
   default resolves the window from the user's most recent commit (committer
   date) in this repo.

   ```
   ${CLAUDE_PLUGIN_ROOT}/skills/whats-new/scripts/whats-new.sh [--since=<period>]
   ```

2. Read the markdown output and prepend a 1–3 bullet TL;DR above it. Surface
   whatever is most actionable:
   - Remote branches whose names look similar to the user's current WIP —
     they may have already pushed this work from another machine or a
     colleague is duplicating it.
   - Stale open MRs in "MRs awaiting my review" (high age).
   - Failing CI on the default branch.
   - Lines beginning with `> note:` — surface those; they explain
     degraded modes (offline, unknown-forge origin, missing CLI, missing identity, etc.).

   If nothing stands out, skip the TL;DR and let the sections speak for
   themselves.

3. Answer follow-up questions conversationally. `Bash(git:*)`,
   `Bash(glab:*)`, and `Bash(gh:*)` are in `allowed-tools` for this step —
   use them directly for things like "show me the diff for that branch",
   "what's in MR !1234" (GitLab), or "what's in PR #456" (GitHub) rather
   than re-running the summary script.

## Notes

- The script is read-only against the repository (it runs `git fetch`, nothing
  else mutates state).
- The script auto-detects the forge (GitHub, GitLab, or unknown) from the
  origin URL, falling back to `gh`/`glab auth status --hostname <h>` probes
  for GitHub Enterprise and self-hosted GitLab.
- If `> note: origin is on GitHub/GitLab but …` appears, surface the install
  hint the script already emitted; the user just needs to run the shown
  `brew install gh` (or apt/dnf equivalent) and `gh auth login` / `glab auth
  login` — and rerun. Don't re-type the hint, the script already did.
- If `> note: no git user.email set and extra_emails is empty …` appears,
  tell the user either to set `git config user.email` in this repo or to
  add addresses to the `extra_emails` userConfig value (via Claude Code's
  plugin-config UI, or by editing `~/.claude/settings.json` directly under
  `pluginConfigs."repo-pulse".options`).
- On unknown-forge origins (Gitea, Codeberg, etc.) the script produces only
  sections 1, 2, and 4 — this is by design, not a bug.
