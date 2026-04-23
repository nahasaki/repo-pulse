# whats-new — delta for configure-summary-model

Adds the `summary_model` userConfig key and extends the existing
parallel-mode subagent dispatch requirement to pass that value as
`Task`'s `model` parameter.

## ADDED Requirements

### Requirement: Configuration — summary_model

The system SHALL expose a `summary_model` userConfig key in
`.claude-plugin/plugin.json` of string type. Allowed values are
`haiku` (default), `sonnet`, `opus`, and `inherit`.

The option SHALL be exposed to the skill as
`CLAUDE_PLUGIN_OPTION_SUMMARY_MODEL`. The value SHALL be validated
before dispatch; an unrecognized value SHALL be treated as `inherit`
AND SHALL trigger a `> note: unknown summary_model value '<value>';
falling back to host session model` line prepended to the themes
section (or to the output if no themes section is produced).

The key affects ONLY parallel-mode subagent dispatch (see the
modified Subagent dispatch rules requirement below). Serial-mode
summarization runs in the host session's model and MUST NOT be
affected by this value — the config description field and SPEC.md
SHALL explicitly document this scope.

#### Scenario: default is haiku

- **WHEN** a user installs or updates the plugin and does not set
  `summary_model`
- **THEN** `summary_model` resolves to `haiku`
- **AND** parallel-mode subagents are dispatched with
  `model: "haiku"`

#### Scenario: user sets inherit

- **WHEN** the user sets `summary_model` to `inherit`
- **THEN** parallel-mode `Task` invocations omit the `model`
  parameter
- **AND** each subagent inherits the host session's model

#### Scenario: user sets sonnet

- **WHEN** the user sets `summary_model` to `sonnet`
- **THEN** parallel-mode `Task` invocations include
  `model: "sonnet"`
- **AND** subagents run on Sonnet regardless of the host session's
  model

#### Scenario: invalid value falls back to inherit with note

- **WHEN** the env var `CLAUDE_PLUGIN_OPTION_SUMMARY_MODEL` is set to
  `haikuu` (or any value outside `{haiku, sonnet, opus, inherit}`)
- **THEN** the skill treats the value as `inherit` and omits the
  `model` parameter from `Task` calls
- **AND** a `> note:` mentioning the unknown value is emitted
- **AND** the skill does not fail; themes continue to generate

#### Scenario: serial mode is unaffected

- **WHEN** `summary_mode` resolves to `serial` (quiet repo) and
  `summary_model` is set to `haiku`
- **THEN** serial-mode summarization uses the host session's model,
  NOT Haiku
- **AND** no subagents are dispatched

## MODIFIED Requirements

### Requirement: Subagent dispatch rules (parallel mode)

When `parallel` mode is selected, the skill SHALL spawn one subagent per cluster via the `Task` tool with these rules:

- Maximum 8 concurrent subagents. If more clusters exist, process in batches of 8.
- Each subagent receives:
  - A fixed prompt: "Here are N commits by `<author>` with `<type>:` prefix, all touching `<path-root>`. Run `git show <sha>` for each and summarize in one sentence what they collectively accomplish. Reply with exactly one sentence, no preamble, no markdown formatting."
  - Scoped tools: `Bash(git:*)` only. No `gh`, no `glab`, no `Read`.
  - A context cap instruction: "Do not read more than 30 lines of each diff; truncate large file blocks."
  - A `model` parameter taken from the validated `summary_model` userConfig value (`haiku`, `sonnet`, or `opus`). When the value is `inherit`, the `model` parameter SHALL be omitted so the subagent follows the host session.
- Subagents that error or time out MUST NOT fail the whole skill. The skill SHALL discard the failed cluster's summary (the cluster's commits still appear in §1).
- If a non-trivial fraction (≥ 25%) of subagents failed, the skill SHALL emit a `> note:` indicating degraded themes output.

#### Scenario: 12 clusters processed in two batches

- **WHEN** `parallel` mode is selected and clustering produced 12 clusters
- **THEN** the skill spawns subagents in batches of 8
- **AND** the first batch has 8 subagents, the second has 4
- **AND** all 12 theme candidates are collected (subject to the 6-bullet output cap)

#### Scenario: one subagent fails, others succeed

- **WHEN** `parallel` mode spawns 5 subagents and 1 returns an error
- **THEN** the themes section contains 4 bullets (subject to the 6-bullet cap)
- **AND** no `> note:` is emitted (1/5 < 25%)

#### Scenario: many subagents fail — degraded note emitted

- **WHEN** `parallel` mode spawns 8 subagents and 3 return errors
- **THEN** the themes section contains 5 bullets
- **AND** a `> note: themes partially degraded: 3 of 8 clusters failed to summarize` is emitted

#### Scenario: dispatch uses configured summary_model

- **WHEN** `summary_model` resolves to `haiku` and `parallel` mode
  spawns 4 subagents
- **THEN** each of the 4 `Task` invocations includes
  `model: "haiku"`
- **AND** subagents run on Haiku even if the host session is on Opus
  or Sonnet

#### Scenario: dispatch uses inherit when configured

- **WHEN** `summary_model` resolves to `inherit` and `parallel` mode
  spawns 3 subagents
- **THEN** each of the 3 `Task` invocations omits the `model`
  parameter
- **AND** subagents inherit the host session's model
