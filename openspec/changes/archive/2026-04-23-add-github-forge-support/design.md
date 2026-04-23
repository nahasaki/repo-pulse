## Context

`repo-pulse` v0.2.0 ships a single branching point for hosting platforms: `IS_GITLAB=true/false`. That works when you only care about GitLab, but it means ~half the plugin's output disappears on any GitHub repo, and the "non-GitLab" warning reads as blame rather than explanation. The fix is small in size (two new collector paths, one detection block, a handful of UI strings) but the shape matters — we're setting a pattern that a third forge could later slot into if needed.

GitHub's `gh` CLI is feature-complete for what we need: `gh pr list --state=all --json ...`, `gh search prs --review-requested=@me --state=open --json ...`, `gh run list --branch <br> --limit 1 --json ...`. Authentication is via `gh auth login`; multiple hosts (GHE) are supported via `--hostname`. `gh auth status --hostname <h>` returns exit 0/non-zero without a network call, which we use for forge detection on unfamiliar domains.

## Goals / Non-Goals

**Goals:**
- GitHub repos get the same six-section report GitLab repos already get.
- GHE and self-hosted GitLab work via probe-fallback detection, with no explicit configuration.
- Output stays forge-agnostic from a reader's perspective — the prefix character (`#` vs `!`) and §6 label are the only visual tells.
- Install hints are precise ("install gh" vs "install glab") and only appear when they'd be actionable.
- GitLab behavior is preserved byte-for-byte so existing users don't notice.

**Non-Goals:** See `proposal.md` §Non-goals.

## Decisions

### D1: URL-first, then local probe for forge detection

**Alternatives considered:**
- **Always probe** (run both `gh auth status` and `glab auth status` regardless of URL). Simpler code but wasteful when URL is obvious.
- **URL-only** (never probe). Fast and simple but misses GHE / self-hosted GitLab entirely — exactly the cases worth covering.

**Choice:** URL-first (`gitlab.com` / `github.com` in origin URL → match immediately). On unmatched URLs, probe `gh auth status --hostname <domain>` then `glab auth status --hostname <domain>`. All probes are local (no network); they read the CLI's auth config and print "Logged in to <host>" when the hostname is registered and authed. **Important spike finding:** both CLIs exit 0 regardless of auth status, so detection must grep stdout/stderr rather than check the exit code. Pattern: `gh/glab auth status --hostname <h> 2>&1 | grep -q 'Logged in to <h>'`.

**Rationale:** the URL check handles 99% of real repos at zero cost. The probe catches the GHE/self-hosted cases that URL-matching alone couldn't. If both probes fail, `forge = unknown` and we fall through to git-only silently.

**Risk:** older `glab` versions may not support `auth status --hostname <h>`. Mitigation documented in Risks below.

### D2: Domain extraction from origin URL

Extract the domain from the origin URL once, upfront, regardless of URL form (ssh: `git@github.com:owner/repo.git`, https: `https://github.com/owner/repo.git`, git: `git://…`). Use a small awk/sed that handles all three. This is fed to both the URL-match phase and the probe phase.

### D3: Dispatch via `case $FORGE in ...`, not a provider abstraction

**Alternatives considered:** provider files (e.g., `scripts/lib/provider-github.sh`) sourced based on `FORGE`.

**Choice:** inline `case` statements in each of the three affected collectors (§3, §5, §6).

**Rationale:** for two forges, the abstraction costs more readability than it saves. A reader wanting to understand what happens on GitHub reads one function, not three files. Revisit only if a third forge (Gitea, Bitbucket) actually lands.

### D4: GitHub reviewer inbox via `gh search prs`, not `gh pr list`

**Choice:** `gh search prs --review-requested=@me --state=open --json number,title,author,createdAt,repository --limit 100`.

**Rationale:** `gh pr list --reviewer` would be scoped to the current repo only; the reviewer inbox should include PRs across all repos the user has review-requests on (matches GitLab's `glab mr list --reviewer=@me` semantics, which also searches across projects). GitHub's `search prs` API supports the `review-requested:` qualifier directly.

### D5: GitHub "Merged this period" uses the search API too

**Choice:** `gh pr list --state=merged --search "merged:>=<ISO-start>" --json ...` for the current repo.

**Rationale:** `--search` supports date qualifiers natively (`merged:>=YYYY-MM-DDT…Z`), so we don't fetch all merged PRs and filter client-side. Same efficiency characteristic as the GitLab path.

### D6: GitHub §6 shows latest workflow run on default branch

**Alternatives considered:**
- Show aggregated "checks status" for the HEAD commit on default (via `gh api`).
- Show the most recent run regardless of branch.

**Choice:** `gh run list --branch <default> --limit 1 --json databaseId,displayTitle,status,conclusion,workflowName,createdAt,htmlUrl`.

**Rationale:** mirrors GitLab's "last pipeline on default branch" semantics. The workflow name is displayed in the output line so users can tell what was measured. Aggregated checks would be more accurate for "is the branch currently green?" but conceptually different from §6's purpose (a single latest CI datapoint).

**§6 line format:**
- GitLab: `- #<pipeline-id> <status> — YYYY-MM-DD HH:MM (<url>)`
- GitHub: `- <workflow-name> #<run-id> <status> — YYYY-MM-DD HH:MM (<url>)`

### D7: Number prefix `#` for GitHub, `!` for GitLab

**Choice:** adapt per forge; don't normalize.

**Rationale:** `!1234` and `#1234` are each native to their forge. Users paste these into terminals and chat, and `#` on GitHub links to the PR automatically in many surfaces (GitHub comments, Slack, etc.). Normalizing to one breaks copy-paste on the other.

### D8: Install hints only for recognized forges

**Choice:** a known-forge-CLI-missing combo emits a multi-line `> note:` with brew/apt/dnf commands and `<tool> auth login`. Unknown forge → no hint.

**Rationale:** for GitLab and GitHub we can give accurate package names. For "your origin is `git.company.com`" we can't know whether to suggest `gh`, `glab`, a Gitea CLI, or nothing. Don't guess.

### D9: GitLab collectors stay call-for-call identical

**Choice:** no refactor of existing `collect_section3` / `_5` / `_6` GitLab paths. Wrap in `case` and leave bodies untouched.

**Rationale:** byte-level preservation of known-working behavior. Any future refactor should be its own change. Diff stays reviewable.

### D10: Version bump to 0.3.0

**Choice:** minor bump. Not a breaking change — no existing user sees degraded behavior.

### D11: `allowed-tools` addition

Adding `Bash(gh:*)` to `SKILL.md` frontmatter so Claude can answer follow-up questions ("what's in PR #123", "show me the diff for that branch") without per-invocation permission prompts. Mirrors the existing `Bash(glab:*)` entry.

## Risks / Trade-offs

- **Risk:** `glab auth status --hostname <h>` may not exist in older `glab` versions.
  → **Mitigation:** probe with `glab auth status --hostname <h> 2>/dev/null`; if that fails for a non-usage reason, fall back to `glab auth status 2>&1 | grep -qi "<h>"`. Test during apply with the installed `glab` version; record findings in design.md §Open Questions or amend to script.

- **Risk:** `gh search prs` uses the Search API (10 req/min rate limit vs 5000/hr for REST) — far more restrictive.
  → **Mitigation:** we make one `search prs` call per invocation; a user running the plugin 10×/minute is implausible. Document the specific rate limit in `design.md` if it ever becomes an issue.

- **Risk:** GHE instances can have custom auth that `gh auth status` handles but `gh api` calls may fail (VPN-gated, cert issues).
  → **Mitigation:** if any `gh` data call fails after detection said "we're on GitHub", emit a `> note:` with the failure summary and continue with empty §3/§5/§6. Don't exit non-zero.

- **Risk:** origin URL with unusual form (gitlab subdomain like `gitlab.example.com`, or GitHub Enterprise as `github.acme.corp`).
  → **Mitigation:** D1's URL-first phase matches the fixed strings `gitlab.com` / `github.com` only; everything else falls through to probes. A GitHub Enterprise at `github.acme.corp` is detected when `gh auth status --hostname github.acme.corp` returns 0.

- **Risk:** a CLI is installed but not authed for this hostname. Example: user has `gh` globally auth'd to github.com, but works in a GHE repo where they haven't logged in.
  → **Mitigation:** `gh auth status --hostname <h>` returns non-zero in this case, so detection falls through correctly. Install hint would suggest `gh auth login --hostname <h>` (include this in the GHE-specific hint).

- **Risk:** forge-detection probes run even when the user explicitly doesn't care (origin is Gitea; they want git-only and nothing else).
  → **Mitigation:** probes are local and fast (tens of ms); not worth an escape hatch for v0.3.

- **Risk:** Section 4 identity resolution regex might not match GitHub noreply addresses (`12345+username@users.noreply.github.com`) if the user commits from the web UI with a different email than their configured `git config user.email`.
  → **Mitigation:** mention in `README.md` that `extra_emails` should include `…users.noreply.github.com` addresses if relevant. No script change.

## Migration Plan

Additive; no migration. Rollout:

1. Update `plugin.json` version to `0.3.0`.
2. Add detection block, refactor sections §3/§5/§6 with `case` dispatch.
3. Update `SKILL.md` `allowed-tools` and body notes.
4. Doc sweep (SPEC.md scope/data-collected/error-handling, README.md positioning).
5. Acceptance: run against GitLab repo (verify no regression), GitHub repo (verify new sections), unknown-forge repo (verify no hint spam).

Rollback: revert the commit; users re-get v0.2.0 behavior.

## Open Questions

- **GHE hint wording.** Should the hint for a GHE repo where `gh` is present but unauthed for that host say `gh auth login --hostname <host>` (host-specific) or just `gh auth login` (interactive pick)? Script will generate the host-specific form; verify it during apply acceptance.
- **Older `glab auth status` flag support.** Resolve in Task 1 (spike), record finding in design.md (amend after apply if needed).
- **Section 3 "Open — mine" filter.** Today on GitLab we match by GitLab username (`glab api /user`). On GitHub, matching by `gh api user` username. Confirm that `.author.login` on PR objects equals the authenticated user's login (it should, but verify).
