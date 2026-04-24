# repo-pulse

> A Claude Code plugin that catches you up on a git repository since you were last active.

Ask *"what's new?"* in any repo and get a **short prose brief** — what
the team shipped, what's in flight (with a heads-up if someone's
already working on your thing), what needs your review, and what you
did. PR and branch references are clickable. One read-only command.

## Example

```
# What's new in cli
Window: 2026-04-21 → 2026-04-24 (--since=3 days ago)

Over the past three days the team landed three big threads: William Martin
shipped a telemetry stack ([telemetry command](...), error recording,
host categorization — [#13253](...), [#13254](...), [#13255](...));
Sam Morrow tightened skill discovery ([#13235](...), [#13236](...),
[#13237](...)); and security hardening landed ([#13272](...) log injection
+ [#13258](...) yaml shell injection).

In flight: Sam has [#13266](...) and [#13264](...) open continuing the
skill-discovery thread. Babak opened [#13271](...) to sign APT repos and
[#13261](...) to URL-escape path components. None of the open PRs overlap
with your current branch.

Nothing awaits your review. CI on `trunk` is green (last run 4h ago).
```

## Features

- **Prose-first output** — 1–4 short paragraphs (Shipped, In flight,
  Needs you, You) instead of scannable but dense bulleted sections
- **Collision heads-up** — if a teammate's open PR or new branch
  overlaps with your current work, it's flagged explicitly
- **Clickable references** — PR numbers and branch names are rendered
  as markdown links that open in your forge
- **Auto-detects your forge** — GitHub (via `gh`) or GitLab (via `glab`),
  including GitHub Enterprise and self-hosted GitLab
- **Smart time window** — defaults to your last commit in the current repo;
  falls back to a configurable period otherwise
- **Cheap by default** — parallel-mode diff summarization uses Haiku
  unless you change `summary_model`
- **Zero-config for most users** — `git config user.email` identifies you
  automatically
- **Graceful degradation** — on unknown forges (Gitea, Codeberg, …) only the
  git-based data is available, with install hints for recognized hosts
- **Read-only** — fetches refs, nothing else

## Install

```
/plugin marketplace add nahasaki/repo-pulse
/plugin install repo-pulse@repo-pulse
```

That's it. Open any git repo in Claude Code and ask *"what's new?"*.

## Update

Pull the latest release from the marketplace and reload:

```
/plugin update repo-pulse@repo-pulse
/reload-plugins
```

`/reload-plugins` applies changes to `plugin.json`, `SKILL.md`, and
the script inside the current Claude Code session — no restart
required. If you want a clean slate, quit and reopen Claude Code
instead.

To see the currently installed version, run `/plugin list` and look
for `repo-pulse`.

## Usage

Slash command:

```
/repo-pulse:whats-new [--since=<period>]
```

`<period>` accepts anything `git log --since` does: `2 weeks ago`,
`yesterday`, `2026-04-01`, …

Natural language (auto-invokes the skill):

- *"what's new in this repo"*
- *"catch me up"*
- *"what did the team do this week"*

## Requirements

- **git** — always required
- **[gh](https://cli.github.com/)** — only if your origin is on GitHub. The
  plugin prints an install hint if it's missing.
- **[glab](https://gitlab.com/gitlab-org/cli)** — only if your origin is on
  GitLab.

On unknown forges the plugin silently falls back to git-only output.

## Configuration

Both values are optional. On first install Claude Code prompts for them, and
they persist in `~/.claude/settings.json` across `/plugin update`.

| Key | Purpose | Default |
|---|---|---|
| `extra_emails` | Additional commit email addresses (if you've used old work or personal addresses) | `[]` |
| `default_since` | Fallback window when your last commit can't be found | `7 days ago` |
| `summary_mode` | Themes section mode: `auto` (threshold-based), `off` (skip themes), `always` (force parallel subagents) | `auto` |
| `summary_max_commits` | Hard safety cap — skip themes when more than this many commits remain after filtering | `50` |
| `summary_model` | Model for parallel-mode themes subagents: `haiku`, `sonnet`, `opus`, or `inherit` (match session). Parallel-only — serial mode always uses your session's model | `haiku` |

Re-run the plugin's config flow in Claude Code to change values later.

## How it works

1. Detects the forge from `origin` URL; falls back to probing `gh`/`glab auth status`
   for GitHub Enterprise and self-hosted GitLab
2. Resolves the time window from your most recent commit, or from `default_since`
3. Runs `git fetch` and a handful of `git log`/`gh`/`glab` queries in parallel
4. Emits one markdown report; the skill prepends a short TL;DR highlighting
   stale reviews, failing CI, or branches that collide with your WIP

## Links

- [SPEC.md](./SPEC.md) — design and behavior, source of truth
- [CLAUDE.md](./CLAUDE.md) — orientation for contributors and agent sessions
- [Issues](https://github.com/nahasaki/repo-pulse/issues)

## Conventions

English for all code, comments, commit messages, and documentation.
Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`).
