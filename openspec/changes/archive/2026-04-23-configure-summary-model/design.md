## Context

The 0.4.0 `whats-new` skill spawns up to eight `Task` subagents per
invocation for cluster summarization. Each subagent reads commit
diffs, follows a fixed prompt ("one sentence, no preamble"), and
returns a short string. Model selection today is implicit — the host
session's model is inherited. On typical setups (Opus or Sonnet)
that's 3–15× more expensive than Haiku per subagent, for a task
where Haiku is known to be sufficient.

This change adds a `summary_model` userConfig key that the skill
passes through to `Task` invocations. The mechanism exists already:
`Task` accepts a `model` parameter (`haiku | sonnet | opus`) that
overrides the default. We just need to expose it.

## Goals / Non-Goals

**Goals:**

- Make the themes feature cheap-by-default for users who don't tune
  the knob.
- Let users who care opt back into richer prose (Sonnet/Opus) or
  match the host session (`inherit`).
- Document clearly that the knob only affects parallel-mode
  summarization — serial mode uses the host session's model.
- Validate the value; fall back safely on typos with a `> note:`.

**Non-Goals:**

- Auto-picking a model per cluster size or content.
- Overriding the model in serial mode (not possible mid-session).
- Per-cluster model variance.
- Exposing model choice for other skill steps (TL;DR, conversational
  follow-ups — those run in the host session too).

## Decisions

### D1. Default is `haiku`

Alternatives considered:

1. **`haiku` default** — chosen. The feature's ethos is token-
   conscious; the default should align. Haiku 4.5 handles the
   summarizer prompt well in practice.
2. **`inherit` default** — rejected. Inherits whatever the user
   picked for the session, which defeats the purpose of the knob
   for most users (who don't know to change it).
3. **`sonnet` default** — rejected. Middle ground but worse than both
   alternatives: more expensive than Haiku, less consistent than
   `inherit`.

### D2. Enum values: `haiku | sonnet | opus | inherit`

We expose four values, not three. `inherit` is explicitly an option,
not a default, because some users want consistency with their
session's model.

Alternatives:

1. **Three model names only** — rejected. Users wanting "same as my
   session" would have to guess what that is and duplicate it in the
   config. Brittle.
2. **Add `sonnet-thinking` or version-pinned variants** — rejected.
   Explicit version pins rot fast as new models ship. The three
   canonical names stay evergreen.

### D3. Invalid values fall back to `inherit`, not `haiku`

If someone types `haikuu` or `gpt-4` into the config, we pick
`inherit` (no `model` field sent to `Task`) and emit a `> note:`.

Alternatives:

1. **Fall back to `inherit`** — chosen. `inherit` is safest because
   it definitely exists (whatever the host session uses does). Also
   gives a visible "something is off" signal because the user's
   intent (probably saving money) isn't reflected in behavior.
2. **Fall back to `haiku`** — rejected. Assumes user wanted the
   default; could silently run the wrong model.
3. **Fail the invocation** — rejected. Themes failure blocking the
   whole skill output is a bad UX for a typo.

### D4. Parallel-only scope, prominently documented

The skill's serial mode reads diffs in the host session; the LLM
reading those diffs is whatever the user picked for the session. We
cannot downgrade to Haiku mid-session. This limitation must be in
the `description` field of the userConfig (so it shows in the plugin
config UI), in SPEC.md, and in the README.

Alternatives:

1. **Document serial-mode exemption** — chosen.
2. **Also force `summary_mode: always` when `summary_model != inherit`** —
   rejected. That would surprise users who set a model but expect
   their existing `summary_mode` preference to stick. Two knobs =
   two separate decisions.
3. **Silently spawn a subagent for serial-mode summarization to apply
   the model** — rejected. Complicates the pipeline; defeats the
   context-preservation tradeoff serial mode exists for (simple,
   inline reads).

### D5. String type with enum-in-description

Per the existing CLAUDE.md gotcha ("userConfig values are always
strings"), we can't declare an enum directly. The type is `string`,
the allowed values go into the description, and the skill validates.

Alternatives considered were:

1. **String type + skill-side validation** — chosen. Matches
   `summary_mode` precedent.
2. **Wait for native enum support from Claude Code** — rejected.
   Blocks the change on an external timeline.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Haiku misreads a complex cluster and emits a misleading sentence | Clusters are already bounded: 30-line-per-file diff cap, single conventional-commit-type + author + path. Haiku has enough context for this scope. Worst case = one awkward bullet; the §1 commit list is authoritative. |
| Users confused why their setting didn't help in serial mode | Parallel-only scope is in the config description, SPEC.md, and README. `summary_mode: always` is the hint for "cost-conscious on every run". |
| New model names appear (e.g., Haiku 5) and enum becomes outdated | The three canonical names (`haiku`, `sonnet`, `opus`) are evergreen in Claude Code's `Task` tool API. When new generations ship, those names continue to point at the latest. If Anthropic introduces a fourth tier someday, we add it. |
| User inputs a version-pinned string like `claude-haiku-4-5` | Validation rejects it → falls back to `inherit` + `> note:`. User sees the note and fixes. Safe. |
| `Task` tool rejects the `model` parameter on a future Claude Code version | Skill should not assume `Task` supports `model` forever — but that's a breaking change Anthropic would announce. If it happens, we drop the field and document the regression. Low probability for 0.5.0 horizon. |
| Inconsistent prose quality between runs with different settings | Acceptable and expected. Users who want consistency set `inherit`. |

## Migration Plan

Additive. No migration needed.

- Users on 0.4.0 upgrading to 0.5.0 without setting
  `summary_model`: parallel-mode subagents silently switch to Haiku.
  Observable effect: themes prose gets slightly terser; cost drops.
- Users who prefer the old behavior set `summary_model: inherit`.
- Rollback: set `summary_model: inherit` (no redeploy needed).

## Open Questions

None. The explore session resolved default, enum shape, scope
(parallel-only), and validation behavior.
