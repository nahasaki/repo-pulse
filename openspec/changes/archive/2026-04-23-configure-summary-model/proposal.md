## Why

The themes pipeline added in 0.4.0 spawns up to eight `Task`
subagents per invocation. Each subagent reads a cluster's `git show`
output and emits one sentence. Today those subagents inherit the host
session's model — typically Opus or Sonnet — which is massive
overkill for a "summarize into one sentence" task and is the single
biggest contributor to the feature's token cost. A smaller model
(Haiku) handles the task well at a fraction of the cost, and is
selectable per-invocation via the `Task` tool's `model` parameter.
Exposing a `summary_model` userConfig key turns a silent default into
a user-controllable knob, lets power users opt back into richer
models when they want them, and makes the feature's cost
characteristics predictable.

## What Changes

- Add a new `summary_model` userConfig key to
  `.claude-plugin/plugin.json`. Allowed values: `haiku` (default),
  `sonnet`, `opus`, `inherit`. Stored as string type (env-var
  constraint); the skill parses and validates.
- Extend the skill's parallel-mode dispatch (`SKILL.md` §Parallel
  mode) to pass `model: <value>` to each `Task` invocation. When the
  value is `inherit`, omit the `model` parameter so the subagent
  follows the host session.
- Validate the userConfig value in the skill. Unknown values fall back
  to `inherit` and the skill emits a `> note:` flagging the unknown
  value — analogous to how invalid `summary_mode` is already handled.
- Update `SPEC.md` §Configuration to document the new key and its
  **parallel-only** scope: serial-mode summarization happens in the
  host session and cannot be downgraded mid-session.
- Update `README.md` configuration table and `CLAUDE.md` gotchas if
  anything new emerges during implementation.
- Bump plugin version to **0.5.0** (additive feature, not breaking).

## Capabilities

### New Capabilities
<!-- None. This change modifies the existing whats-new capability. -->

### Modified Capabilities
- `whats-new`: add one new requirement (`Configuration — summary_model`)
  and modify the existing `Subagent dispatch rules (parallel mode)`
  requirement to include the `model` parameter. Delta spec lives
  under `specs/whats-new/spec.md` of this change.

## Impact

- `.claude-plugin/plugin.json` — one new `userConfig` entry; version
  bump.
- `skills/whats-new/SKILL.md` — §Parallel mode gets a "Model
  selection" sub-section and the subagent dispatch example gains a
  `model` field.
- `SPEC.md` — one new row in §Configuration table; one-paragraph
  subsection noting the parallel-only scope.
- `openspec/specs/whats-new/spec.md` — synced at archive time with
  the ADDED/MODIFIED requirements from this change's delta.
- No changes to `whats-new.sh` — the script remains unaware of the
  summarizer model; it's a skill-layer concern.
- No user-visible output changes unless the user explicitly overrides
  the default.

## Non-goals

- No "auto-pick model based on cluster size" logic. One setting, one
  value. Tuning a smarter auto-selector would belong in a later
  change and needs real data first.
- No model override for serial mode. Serial runs in the host
  session's model — impossible to swap without a protocol change.
  The config documentation makes this explicit.
- No per-cluster model override. The value applies uniformly to all
  subagents in a run.
- No config key for the subagent's system prompt, tool scope, or
  context cap. Those remain fixed in `SKILL.md`.
- No telemetry or reporting of which model was used. Users can
  inspect `settings.json` if they want to verify.
