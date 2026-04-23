# CLAUDE.md

Orientation for agent sessions working on the `repo-pulse` plugin.

All code, comments, commit messages, and documentation in this repo must be
written in English.

## What This Repo Is

A Claude Code **plugin** named `repo-pulse`, distributed as a standalone git
repository. The repo root is also the plugin root — one repo, one plugin.
There is no umbrella marketplace structure.

The plugin's purpose and design are defined in [`SPEC.md`](./SPEC.md).
Treat `SPEC.md` as the source of truth: if a question has an answer there,
follow it; if not, extend the spec before implementing.

## Repository Layout

Intended structure once v0.1.0 is implemented:

```
repo-pulse/                          (git repo root = plugin root)
├── .claude-plugin/
│   ├── plugin.json                  # plugin manifest
│   └── marketplace.json             # optional: make repo a 1-plugin marketplace
├── SPEC.md                          # design source of truth
├── README.md                        # short intro + install
├── CLAUDE.md                        # this file
└── skills/
    └── whats-new/
        ├── SKILL.md                 # frontmatter + body for the skill
        └── scripts/
            └── whats-new.sh         # entry point (chmod +x)
```

User config lives in `plugin.json` `userConfig`, not in files in the skill
tree. The harness persists values in `~/.claude/settings.json` and exposes
them to the script as `CLAUDE_PLUGIN_OPTION_<KEY>` env vars. See SPEC.md
§Configuration.

## Conventions

### Plugin manifest

`.claude-plugin/plugin.json` at the repo root. Minimum fields:

```json
{
  "name": "repo-pulse",
  "version": "0.1.0",
  "description": "Summarize git activity in the current repository.",
  "author": { "name": "Myroslav Tantsyura" }
}
```

`name` must stay `repo-pulse`. Bump `version` with semver on releases.

### Skill file references

Skills that invoke bash scripts must reference them through
`${CLAUDE_PLUGIN_ROOT}` — Claude Code sets this to the plugin's cached
install path at runtime. Example in `SKILL.md` frontmatter:

```yaml
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/whats-new/scripts/whats-new.sh:*)
```

Never hard-code absolute paths like `/Users/<name>/…`. Plugins installed
via `/plugin install` are copied into `~/.claude/plugins/cache/`, so the
source tree is not where the plugin actually runs.

### Scripts

- All bash scripts live under `skills/<skill>/scripts/`
- Must be `chmod +x` — commit the executable bit
- Use `set -euo pipefail` at the top unless a specific section needs
  different error semantics; document the exception in-line
- Keep one script per entry point; extract helpers into `scripts/lib/` only
  when the entry point exceeds ~200 lines

### Persistent state

If a later change needs to persist state across invocations (caches,
timestamps, user choices), write to `${CLAUDE_PLUGIN_DATA}`. Never write
into the plugin directory at runtime — it is read-only when installed.
v0.1.0 does not need persistent state.

### Git

- Conventional Commits: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`.
  Scope is omitted (the whole repo is one plugin)
- The user reviews every commit — **never `git commit` without an explicit
  instruction**
- Do not commit `.env`, credentials, or `config.local.sh`

### Language and documentation style

- English only for everything checked in
- Conversation with the user may happen in Ukrainian, but artifacts stay
  English
- `SPEC.md` is the design doc; `README.md` is a short intro for humans; this
  file is for agents
- Keep docs focused — no filler, no redundant restatement across files

## Install And Iterate

### Dev workflow (recommended during iteration)

```bash
claude --plugin-dir ~/Projects/claude-plugins/repo-pulse
```

Inside the session, after edits:

```
/reload-plugins
```

This loads the plugin directly from the source tree. Symlinking into
`~/.claude/plugins/` is not supported.

### Install as a marketplace of one (for daily use)

Add `.claude-plugin/marketplace.json` at the repo root:

```json
{
  "name": "repo-pulse",
  "owner": { "name": "Myroslav Tantsyura" },
  "plugins": [
    { "name": "repo-pulse", "source": ".", "description": "…" }
  ]
}
```

Then:

```
/plugin marketplace add ~/Projects/claude-plugins/repo-pulse
/plugin install repo-pulse@repo-pulse
```

Updates: edit files, `git commit`, then `/plugin update repo-pulse@repo-pulse`.

## Implementation Status

v0.1.0 (archived change `implement-whats-new`) delivered the working skill
end-to-end. v0.2.0 (change `adopt-user-config`) migrated user config from
shipped shell files to Claude Code's `userConfig` mechanism — see SPEC.md
§Configuration for the current model. See `openspec/changes/archive/` for
history and `openspec/specs/whats-new/spec.md` for the current
specification.

When starting new work, propose a change via `/opsx:propose` rather than
extending this file with ad-hoc plans. CLAUDE.md describes orientation; the
change directory carries the work-in-progress.

## Historical notes

Acceptance for v0.1.0 and v0.2.0 used these targets — keep them in mind
when regression-testing future changes:

- Run against `promin/funnels-builder`, a GitHub repo, and an empty-window
  case (see SPEC.md §Testing).
- For v0.2.0, also verify first-run `userConfig` prompt, survival of
  `/plugin update`, and the dev-mode `config.local.sh` fallback.

Commit each logical step separately so the history is reviewable.

## Out Of Scope

The Non-Goals section of `SPEC.md` is authoritative. Do not expand scope
without updating the spec first.
