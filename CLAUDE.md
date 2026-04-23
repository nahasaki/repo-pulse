# CLAUDE.md

Orientation for agent sessions working on the `repo-pulse` plugin.

All code, comments, commit messages, and documentation in this repo must be
written in English.

## What This Repo Is

A Claude Code **plugin** named `repo-pulse`, distributed as a standalone git
repository. The repo root is also the plugin root — one repo, one plugin.
Current version lives in `.claude-plugin/plugin.json`. Published at
`nahasaki/repo-pulse` on GitHub.

Sources of truth, in order:

- [`SPEC.md`](./SPEC.md) — design and behavior. If a question has an answer
  there, follow it; if not, extend the spec before implementing.
- `openspec/specs/whats-new/spec.md` — current capability spec (requirements
  + scenarios). Tightly coupled to script behavior.
- `openspec/changes/archive/` — chronological history of completed changes
  (proposal + design + tasks per change). Preferred over maintaining a
  running log in this file.

## Repository Layout

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

Live at `.claude-plugin/plugin.json`. `name` must stay `repo-pulse`. Bump
`version` with semver on releases (minor bump for breaking changes while
we're pre-1.0). `userConfig` shape is documented in `SPEC.md`
§Configuration — don't inline it here, it rots.

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
- Commit each logical step separately so the history is reviewable

### Language and documentation style

- English only for everything checked in
- Conversation with the user may happen in Ukrainian, but artifacts stay
  English
- `SPEC.md` is the design doc; `README.md` is a short intro for humans; this
  file is for agents
- Keep docs focused — no filler, no redundant restatement across files

## Gotchas

Things that cost implementation time — don't re-learn:

- **macOS default bash is 3.2.** `#!/usr/bin/env bash` picks up Homebrew's
  bash 4+ when present. Avoid bash 4+ features like `${var^}`, `${var,,}`,
  `declare -n`, or `++` inside awk subscripts in BSD awk.
- **`gh auth status` and `glab auth status` always exit 0** regardless of
  auth state. Parse stdout for `Logged in to <host>`, don't trust the exit
  code. See `auth_hostname_matches` in `whats-new.sh`.
- **Git's approxidate misparses `--since=7d`** as "the 7th day of the
  month", not "7 days ago". The script resolves SINCE to `@<unix>` epoch
  form before passing to `git log` to avoid this.
- **`git log --author` uses BRE by default** — `|` is literal. Use
  `--extended-regexp` for OR-join of emails.
- **`gh run list` has no `htmlUrl` field** — it's `url`. Always verify
  field names with `gh <cmd> --json help` before relying on them.
- **`git for-each-ref refname:short`** returns `origin` (not `origin/HEAD`)
  for the origin/HEAD symbolic ref on some git versions. Filter by full
  refname, not short.
- **`grep -c` exits 1 on zero matches** while still printing `0`. If you
  shell-substitute its output and `|| printf 0` as fallback you'll emit
  "00". Swallow the exit instead.

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

## Working on changes

Use OpenSpec. Propose via `/opsx:propose <kebab-name>`, implement via
`/opsx:apply <name>`, archive via `/opsx:archive <name>`. Do NOT extend
this file with ad-hoc plans — CLAUDE.md is orientation, the change
directory (`openspec/changes/<name>/`) is work-in-progress.

Read `openspec/changes/archive/` for completed change history.

## Acceptance targets

Concrete paths that have proven useful for acceptance runs:

| Path | Forge | What it exercises |
|---|---|---|
| `~/Projects/promin/funnels-builder` | GitLab | Full 6-section report; identity resolution with multiple emails |
| `~/Projects/inflecto` | GitHub | GitHub §1/§2/§4; low activity (useful for "nothing new" edge) |
| `/tmp/cli-test` (shallow clone of `cli/cli`) | GitHub | Active §3/§5/§6: PRs, search, workflow runs |
| `/tmp/wn-unknown` (fake Codeberg origin) | unknown | Verifies silent git-only path |

Shallow clone for `cli-test`:

```bash
git clone --depth 30 https://github.com/cli/cli.git /tmp/cli-test
```

For `userConfig` + `/plugin update` survival, a real marketplace install
(`/plugin install repo-pulse@repo-pulse`) in a fresh Claude Code session
is required — cannot be simulated from `--plugin-dir` sessions.

## Out Of Scope

The Non-Goals section of `SPEC.md` is authoritative. Do not expand scope
without updating the spec first.
