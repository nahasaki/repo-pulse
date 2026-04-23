# repo-pulse

> A Claude Code plugin that catches you up on a git repository since you were last active.

Ask *"what's new?"* in any repo and get a focused brief: what your teammates
merged, which branches moved, which PRs are waiting on you, and whether CI is
green — in one read-only command.

## Features

- **Themes this period** — on active repos, a short "what was actually
  done" section above the commit list, clustered by author and area.
  Threshold-based: cheap on quiet repos, bounded on busy ones via
  parallel subagents
- **Auto-detects your forge** — GitHub (via `gh`) or GitLab (via `glab`),
  including GitHub Enterprise and self-hosted GitLab
- **Smart time window** — defaults to your last commit in the current repo;
  falls back to a configurable period otherwise
- **Surfaces what matters** — merged commits, new/updated branches, open PRs,
  PRs awaiting your review, your own recent work, CI status
- **Zero-config for most users** — `git config user.email` identifies you
  automatically
- **Graceful degradation** — on unknown forges (Gitea, Codeberg, …) only the
  git-based sections run, with install hints for recognized hosts
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
