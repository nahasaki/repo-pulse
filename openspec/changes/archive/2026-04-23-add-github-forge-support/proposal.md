## Why

The plugin is useful to anyone who context-switches across multiple repos — but today it only delivers full value on GitLab-hosted projects. On a GitHub repo the output collapses to three git-only sections plus a "not a GitLab remote" warning, which makes the plugin useless to the ~half of this author's repos that live on GitHub. GitHub's CLI (`gh`) is now well-established, ships by default on many dev machines, and provides API parity for the handful of commands this plugin needs (`pr list`, `pr list --search review-requested:@me`, `run list`). Adding it as a first-class forge brings the plugin from "nice for GitLab work" to "nice for all my work" at modest complexity cost.

While we're at it, two related polish items: silently skipping a forge we don't recognize (Gitea, Codeberg, etc.) instead of blaming the user's GitLab setup; and giving actionable install hints when we DO recognize the forge but the CLI is missing.

## What Changes

- **Replace the single `IS_GITLAB` boolean** in `whats-new.sh` with a `FORGE` variable resolving to `github` / `gitlab` / `unknown`.
- **Add forge detection**:
  - URL-first: `gitlab.com` or `github.com` in the origin URL → match immediately.
  - Fallback probes (local, no network): `gh auth status --hostname <domain>` and `glab auth status --hostname <domain>`, to catch GitHub Enterprise and self-hosted GitLab.
  - Fall through to `unknown`.
- **Rewrite sections §3 (MRs/PRs), §5 (review inbox), §6 (CI status)** to dispatch on `FORGE`:
  - GitLab path: unchanged (`glab` calls as today).
  - GitHub path: equivalent `gh` calls. Output uses `#<number>` prefix instead of `!<iid>`. §6 adaptive label: `- <workflow name> #<id> <status> — …` on GitHub, `- #<pipeline-id> <status> — …` on GitLab.
- **Install-hint matrix** in preflight:
  - `forge = github, gh missing` → `> note:` with install commands for brew/apt/dnf and `gh auth login`.
  - `forge = gitlab, glab missing` → same for `glab` (this is new — today we silently run git-only on unauthenticated GitLab).
  - `forge = unknown` → no hint (don't nag Gitea / Codeberg users).
  - `jq` missing while a forge CLI is present → hint: install jq.
- **Update `SKILL.md` frontmatter**: `allowed-tools` adds `Bash(gh:*)` so follow-up questions ("diff for PR #123", "open that run") don't trip permission prompts.
- **Version bump** to `0.3.0`. This is additive: existing GitLab users see no behavior change; existing GitHub users gain sections that were previously empty.

No change to `plugin.json` `userConfig` — identity resolution is forge-agnostic (based on `git config user.email` + `extra_emails`). No change to the script's read-only contract.

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

- `whats-new`: three existing requirements change and one new requirement is added. See `specs/whats-new/spec.md` for the deltas.

## Impact

- **Files modified**: `.claude-plugin/plugin.json` (version), `skills/whats-new/scripts/whats-new.sh` (forge detection + §3/§5/§6 dispatch), `skills/whats-new/SKILL.md` (`allowed-tools`, body notes), `SPEC.md`, `README.md`, `CLAUDE.md`.
- **New host dependency** (conditional): `gh` for GitHub repos. Not required when origin is non-GitHub.
- **Version bump**: `0.2.0` → `0.3.0` (additive, not breaking).
- **User-visible change on GitHub repos**: the output grows from 3 to 6 sections. On GitLab repos: no visible change. On unknown-forge repos: the noisy "non-GitLab" warning goes away; output is silent about the forge.
- **Rate limits**: `gh` authenticated users have 5000 API requests/hour; the plugin issues 2–3 calls per invocation. Non-concern.
- **Acceptance surface** grows: we now need test runs on a GitHub repo (done informally today — `~/Projects/inflecto`), and ideally on a GHE or self-hosted GitLab if accessible.

## Non-goals

- **Gitea / Codeberg / Bitbucket support.** Users on these forges get git-only sections silently. Adding a dedicated `tea` / `berg` / `bb` path is not worth the maintenance cost for v0.3.
- **Auto-installing the missing CLI.** We print hints, we don't run `brew install`.
- **Merging forges per-repo.** If you push the same repo to both `origin` (GitLab) and a GitHub mirror, we follow `origin` only. No multi-forge aggregation.
- **Different reviewer semantics across forges.** GitLab "reviewer" and GitHub "review-requested" are near-identical; we treat them as equivalent. We do NOT add separate handling for GitHub "requested teams" or CODEOWNERS.
- **Abstracting §3/§5/§6 into pluggable providers** (separate files, interface contracts). A `case $FORGE in ... esac` dispatch is clearer for two forges; abstract only if a third forge ever lands.
- **Changing the output section order or count.** The fixed-order invariant from SPEC.md §Output Format stays — downstream TL;DR logic depends on it.
- **Renaming `extra_emails` or other user config.** Identity config is already forge-agnostic.
