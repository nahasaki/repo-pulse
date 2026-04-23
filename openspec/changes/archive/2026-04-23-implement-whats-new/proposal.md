## Why

The repo currently ships only design docs (`SPEC.md`, `README.md`, `CLAUDE.md`) — the plugin does nothing when loaded. v0.1.0 must deliver the first working version so the target user (who context-switches across ~8 repos) can actually run `/repo-pulse:whats-new` during real daily use and validate the catch-up workflow.

## What Changes

- Add plugin manifest `.claude-plugin/plugin.json` (minimum fields per `CLAUDE.md` §"Plugin manifest").
- Create the `whats-new` skill under `skills/whats-new/`:
  - `SKILL.md` with frontmatter and body per `SPEC.md` §"SKILL.md Sketch".
  - `config.sh` — committed template with empty `MY_EMAILS=()` and `DEFAULT_SINCE="7 days ago"`.
  - `scripts/whats-new.sh` — entry point, `chmod +x`, produces the six-section markdown output per `SPEC.md` §"Data Collected" and §"Output Format".
- Implement the window-resolution logic (smart default based on committer date of the user's most recent commit, fallback to `DEFAULT_SINCE`) per `SPEC.md` §"Invocation".
- Implement error handling per `SPEC.md` §"Error Handling" (non-git, non-GitLab, `glab auth` failure, offline `git fetch`, `jq` missing rules).
- Add `.claude-plugin/marketplace.json` so the repo installs as a marketplace-of-one.
- Run manual acceptance against the three scenarios in `SPEC.md` §"Testing".

This change implements behavior already described in `SPEC.md`; no SPEC.md updates are required as part of it.

## Capabilities

### New Capabilities

- `whats-new`: produces a markdown summary of activity in the current git repository (colleagues' merged commits, new/updated remote branches, GitLab MRs in three buckets, the user's own recent commits, MRs awaiting review, CI status on the default branch) within a configurable time window.

### Modified Capabilities

_None — this is the first implementation._

## Impact

- **New files**: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `skills/whats-new/SKILL.md`, `skills/whats-new/config.sh`, `skills/whats-new/scripts/whats-new.sh`.
- **Host dependencies**: `git` (required), `glab` (optional; required only for GitLab-specific sections), `jq` (required only when origin is GitLab).
- **No changes** to `SPEC.md`, `README.md`, `CLAUDE.md` — they already describe v0.1.0 accurately after the recent revisions.
- **No runtime state**: `${CLAUDE_PLUGIN_DATA}` is not written in v0.1.0.
- **Distribution**: after acceptance, `/plugin install repo-pulse@repo-pulse` works from this repo.

## Non-goals

Per `SPEC.md` §"Non-Goals For v0.1.0":

- Cross-repository aggregation.
- Caching state between runs.
- GitHub support via `gh`.
- Slack / email notifications.
- JSON output mode.
- Configurable section order or per-section toggles.
- Detecting comments on the user's MRs (section 5 covers assignment only).
- Stale-branch cleanup hints.

Each of these is a separate future change once v0.1.0 is proven in daily use.
