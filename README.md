# repo-pulse

Claude Code plugin that summarizes what changed in the current git repository
since you were last active — colleagues' commits on the default branch, new
or updated remote branches, open/merged pull/merge requests, your own recent
commits, PRs/MRs waiting for your review, and CI status on the default
branch.

Works out of the box on GitHub and GitLab — `gh` is used for GitHub
origins, `glab` for GitLab origins. GitHub Enterprise and self-hosted GitLab
are detected via the CLIs' `auth status --hostname <h>` probe. On unknown
forges (Gitea, Codeberg, etc.) only the git-based sections run.

Current version: **0.3.0**. See [`SPEC.md`](./SPEC.md) for the source of
truth.

## Install (dev workflow)

Launch Claude Code with this plugin loaded directly from disk:

```bash
claude --plugin-dir ~/Projects/claude-plugins/repo-pulse
```

Inside the session, after edits to plugin files:

```
/reload-plugins
```

Once the plugin is stable, a `.claude-plugin/marketplace.json` can be added
at the repo root to make this repo its own single-plugin marketplace,
installable via `/plugin install repo-pulse@repo-pulse`.

## Invocation

```
/repo-pulse:whats-new [--since=<period>]
```

Also auto-invokes on prompts like "what's new in this repo", "catch me up",
"what did the team do".

## Configuration

Zero-config on fresh install: `git config user.email` in the current repo
is used automatically as your identity.

On first `/plugin install`, Claude Code prompts for two optional values:

- **Additional email addresses** — only needed if you've committed with
  other addresses (old work email, personal gmail). Skip if `git config
  user.email` already covers you.
- **Fallback time window** — used when the plugin can't find your last
  commit in this repo. Default: `7 days ago`.

Values are persisted in `~/.claude/settings.json` and survive `/plugin
update`. To change them later, re-run the plugin's config flow in Claude
Code (or edit `~/.claude/settings.json` under `pluginConfigs."repo-pulse"`
directly).

For `claude --plugin-dir` dev workflows, see `SPEC.md` §Configuration for
the optional `config.local.sh` fallback.

## Conventions

- English for all code, comments, commit messages, and documentation
- Conventional Commits: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`
- Orientation for agent sessions: [`CLAUDE.md`](./CLAUDE.md)
