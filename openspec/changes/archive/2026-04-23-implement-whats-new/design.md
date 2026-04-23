## Context

`SPEC.md` already defines the plugin's behavior end-to-end (invocation, sections, output format, error handling). This document records the *technical* decisions that aren't fully argued there — things a reader of the script would wonder about, and reasonable alternatives we considered and rejected.

The target user works across ~8 repos on macOS/Linux with stock dev tooling (git, optionally glab, optionally jq). The plugin must work on day one with minimal install friction.

## Goals / Non-Goals

**Goals:**
- Single bash entry point that runs on any machine that already has `git` (and, for GitLab repos, `glab` + `jq`).
- Deterministic, heuristic-free script output. All "what matters?" judgment is Claude's job in the TL;DR step.
- Graceful degradation: missing `glab`, missing `jq`, non-GitLab origin, offline state — each yields a useful subset of output rather than a hard failure.
- Public-repo-safe: no personal data in committed files.

**Non-Goals:**
- Per `proposal.md` §Non-goals (cross-repo, caching, GitHub, JSON output, notifications, etc.).
- Portability beyond POSIX-ish bash 4+. We won't shim for old bash 3 (macOS's default /bin/bash) — the script declares `#!/usr/bin/env bash` and assumes a modern bash is first on PATH, which Homebrew, nix, and most Linux distros satisfy.

## Decisions

### D1: Bash, not Python/Node

**Alternatives considered:** Python (`subprocess` + `argparse`), Node (`execa`), Deno.
**Choice:** bash.
**Rationale:** zero install step. Every dev laptop already has bash, git, and (for GitLab repos) usually glab. A Python/Node rewrite buys testability but costs a new dependency for what is fundamentally a shell pipeline around `git log`, `git for-each-ref`, and `glab`. If the script exceeds ~500 lines or we need real data-modelling, revisit.

### D2: Committer date everywhere, never author date

**Alternatives considered:** author date (git's default semantics in `git log --since`).
**Choice:** committer date for both window resolution and section filtering.
**Rationale:** rebase- and cherry-pick-resilient. When the user rebases their branch, author dates are preserved but committer dates update — using author date would cause the window to "jump backwards" onto commits that already appeared in a previous run. `SPEC.md` §Invocation and §"1. Merged to default" both call this out.

### D3: Two-file config (`config.sh` template + `config.local.sh` local)

**Alternatives considered:** single `config.sh` with placeholder values; `.env` file; XDG config path at `~/.config/repo-pulse/`.
**Choice:** two files co-located with the skill.
**Rationale:** the repo is public — personal emails must not land in git history. XDG was rejected because it separates config from the skill it configures; users would have to hunt for where to put their emails. The current layout keeps the whole skill in one directory and relies on `.gitignore` to keep `config.local.sh` out of commits.

### D4: One entry-point script, `lib/` only when it grows

**Alternatives considered:** split into `section-1.sh`, `section-2.sh`, ... from day one.
**Choice:** single `whats-new.sh`; extract to `scripts/lib/sections.sh` and `scripts/lib/format.sh` only if the entry point exceeds ~200 lines (per `CLAUDE.md` §Scripts).
**Rationale:** v0.1.0 needs to be readable top-to-bottom. Premature splitting hurts discoverability when the whole thing fits on one screen.

### D5: Collect independent sections in parallel

**Alternatives considered:** purely sequential execution.
**Choice:** run git-only sections, glab calls, and CI pipeline query as parallel bash background jobs, then `wait` and assemble.
**Rationale:** wall-clock latency matters — the user is blocking on this output. The sections are independent, so parallelism is free. Use tempfiles per section to avoid interleaved stdout.

### D6: `glab mr list -F json` + `jq`, not per-MR calls

**Alternatives considered:** paginated `glab mr list` followed by N `glab mr view` calls.
**Choice:** single JSON dump, filter in the script.
**Rationale:** one network round trip; no rate-limit concerns. This is why `jq` is a hard requirement when origin is GitLab.

### D7: `--updated-after` when available, client-side filter otherwise

**Alternatives considered:** always client-side filter.
**Choice:** probe for `--updated-after` support at runtime; if `glab mr list --updated-after 1970-01-01 -F json 2>/dev/null` succeeds, use it; otherwise fetch the full set and filter on `updated_at` in the script.
**Rationale:** keeps the script working across older `glab` versions while benefiting from the server-side filter when available.

### D8: Markdown output, not JSON

**Alternatives considered:** JSON output with a formatter downstream.
**Choice:** plain markdown to stdout.
**Rationale:** Claude reads markdown natively and can excerpt it; a human piping to `less` gets a readable report; section boundaries stay obvious. JSON is deferred to a later change (see Non-goals).

### D9: Auto-detect default branch, no config override

**Alternatives considered:** `DEFAULT_BRANCH` in `config.sh` as an escape hatch.
**Choice:** always `git symbolic-ref refs/remotes/origin/HEAD`, fallback `main`.
**Rationale:** every repo has a different default branch; forcing the user to configure per repo defeats the whole point. Auto-detection already handles the cases that matter.

## Risks / Trade-offs

- **Risk:** `MY_EMAILS` empty on first run (user installed but hasn't created `config.local.sh`) → smart default has nothing to anchor on.
  → **Mitigation:** fall back to `DEFAULT_SINCE` (7 days), still produce sections 1/2/3/5/6; print a `> note:` hint that section 4 will stay empty until `MY_EMAILS` is configured.

- **Risk:** bash 3 on macOS (system `/bin/bash`) breaks `MY_EMAILS=()` arrays and `[[` extensions in subtle ways.
  → **Mitigation:** `#!/usr/bin/env bash` so Homebrew's bash 4+ is picked up when present. Document in README that bash 4+ is expected.

- **Risk:** parallel bash jobs can interleave stderr and corrupt error messages.
  → **Mitigation:** each parallel section writes stdout to its own tempfile; stderr is collected per job and printed after `wait`.

- **Risk:** `glab mr list` on huge projects returns large JSON payloads and slows the script.
  → **Mitigation:** prefer `--updated-after` when supported (D7); if client-side filtering, at least constrain to the same window.

- **Risk:** committer date as window anchor surprises users ("why did my new merge commit shift the window?").
  → **Mitigation:** the output header's `<reason>` line spells out exactly what was used (`from your last commit on <ISO date>` vs `--since=X` vs `DEFAULT_SINCE fallback`). `SPEC.md` §Invocation documents the choice.

## Migration Plan

Greenfield change — nothing to migrate. Rollout:

1. Land the files (manifest, skill, script, config template) on a feature branch.
2. Dev-test with `claude --plugin-dir ~/Projects/claude-plugins/repo-pulse` against the three acceptance repos in `SPEC.md` §Testing.
3. Add `.claude-plugin/marketplace.json` once acceptance passes.
4. Merge to `main`; users install via `/plugin marketplace add` + `/plugin install repo-pulse@repo-pulse`.

Rollback is trivial: `/plugin uninstall repo-pulse@repo-pulse`.

## Open Questions

- **Section-2 "commits ahead of default" query shape.** Two candidates: `git rev-list --count origin/<default>..<branch>` per branch (clear, N queries) vs a single `git for-each-ref --format '%(push:track,nobracket)'` pass (one query, harder to read). Decide at implementation time based on readability; performance difference is negligible for realistic branch counts.
- **First-run hint when `MY_EMAILS` is empty.** Should the script emit `> note: MY_EMAILS is empty — section 4 will be blank until you create config.local.sh`? Leaning yes (low cost, high signal for new users), but defer the final call to implementation.
- **`glab ci list` vs `glab pipeline list`.** Need to confirm which verb the current `glab` version exposes for "last pipeline on default branch" in section 6. Resolve when writing section 6.
