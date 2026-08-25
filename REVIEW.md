# REVIEW.md

Repository-specific law for the automated pull-request reviewer (MiniMax, two advisory lanes).

`wild-gap-miner` is an offline Ruby analysis library. It ingests JSON Lines telemetry exports
produced by `wild-session-telemetry`, runs 6 analyzers, scores and ranks capability gaps, and
exports a report as JSON or Markdown. It has zero runtime dependencies, makes no network calls,
and is consumed as a gem by other people's Rails apps. Review with that shape in mind.

Report only findings the pull request introduces, verified against the surrounding source. The
deterministic gate is CI (`bundle exec rspec` on Ruby 3.2 and 3.3, `bundle exec rubocop`). The
reviewer's job is the class of defect those checks cannot see.

## Authority

Read `CLAUDE.md` first. `000-docs/004-AT-ADEC-architecture-decisions.md` governs design questions,
`000-docs/005-DR-REFF-configuration-reference.md` governs config keys and defaults, and
`000-docs/003-TQ-STND-privacy-model.md` governs what may appear in a report. The upstream data
contract (record types, key names) is restated in `CLAUDE.md` under "Upstream Data Contract"; a PR
that changes how a record is parsed is changing a contract with another repo, so say so.

## Top defect classes, in order of risk

1. **A detector that silently stops detecting.** This is the highest-value bug here, because a gap
   miner that reports nothing looks exactly like a healthy system. Hunt inverted or off-by-one
   threshold comparisons (`return nil if rate < config.threshold` flipped to `>`, `<` swapped for
   `<=` at the boundary), a `filter_map` block that returns a falsy value on the reporting path, a
   `limit_gaps` cap applied before ranking instead of after, and any early `return []` guard that is
   broader than the condition it means to guard.
2. **Severity escaping 0.0 to 1.0.** `Models::Gap` raises `ValidationError` outside that range, and
   that exception aborts the entire report, not one gap. Any newly derived severity must pass through
   `clamp_severity` (or `.clamp(0.0, 1.0)`) before it reaches `build_gap`. A ratio, a difference such
   as `1.0 - fraction`, or a weighted product in `SeverityScorer` are all suspect.
3. **An analyzer that raises instead of returning `[]`.** Analyzers must degrade to an empty array
   when their record type is absent, nil, or empty. Flag `records[:x].map` without `Array(...)`,
   arithmetic on a possibly nil count, and division by a size that can be zero (`CoverageAnalyzer`
   divides by `all_actions.size`). Flag any new record accessor that assumes a key is present.
4. **Privacy surface growth.** Per the privacy model, a report carries derived analytics, action
   names, and caller IDs, and nothing else. Flag any change that puts raw tool arguments, file
   contents, prompts, completions, headers, tokens, or free-form upstream payload fields into
   `Gap#evidence`, `#description`, `#recommendation`, or an exporter. Flag any new logging, `puts`,
   `warn`, or exception message that interpolates a raw record. Never reproduce a suspected secret in
   a comment: name the location and the fix.
5. **Untrusted input reaching something that executes.** Export files are attacker-shaped data. The
   only permitted deserializer is `JSON.parse`. Flag `Marshal.load`, `YAML.load` or
   `YAML.unsafe_load`, `eval`, `instance_eval`, `send` with a name taken from record data, `Object.const_get`
   on a record type string, backticks, `system`, `%x[]`, `Kernel.open`, or a path from export content
   interpolated into a filename. Flag `format`/`sprintf` where the format string itself comes from
   record data (the templates in `Recommendations::Engine` are the format string, the action is an
   argument, and that direction must not reverse).
6. **Dependency and reach creep.** The gem declares no runtime dependencies and no network access.
   Flag any `require` outside the Ruby standard library, any addition to `spec.add_dependency`, any
   `Net::HTTP`, `URI.open`, socket, or `ENV` read that changes behavior at runtime.
7. **Ordinary correctness in the pipeline.** Percentile handling in `LatencyAnalyzer`, ratio math,
   `Hash#except`/`merge` key shapes between `ExportParser`, `Report::Builder`, and the analyzers,
   and `GapReport#to_h` shape changes that break `JsonExporter` consumers.

## Invariants that must never regress

- **Severity is bounded.** Every `Gap` has `severity` in `[0.0, 1.0]` and `type` in
  `Models::Gap::VALID_TYPES`. Validation lives in `Gap#initialize` and stays there.
- **Analyzers total.** `Analyzers::Base` subclasses return `Array<Models::Gap>`, never nil, never a
  raise, for any records hash including an empty one.
- **Per-type cap.** Each analyzer emits at most `config.max_gaps_per_type` gaps, chosen after sorting
  by severity descending, so the cap keeps the worst gaps rather than an arbitrary slice.
- **Deterministic ordering.** `Gap#<=>` sorts severity descending, and `GapReport` sorts on
  construction. Two runs over the same export produce the same report ordering.
- **Config is validated and freezable.** Every attribute writer calls `check_frozen!` first, then
  validates before assigning. The seven scalar writers use `validate_float!` or `validate_integer!`
  with their documented bounds; `severity_weights=` is the one exception and does its own
  `is_a?(Hash)` check, raising `ConfigurationError` directly, then merges over
  `DEFAULT_SEVERITY_WEIGHTS`. A new scalar option missing `check_frozen!`, a bounded validator, or an
  entry in `DEFAULTS` and the configuration reference doc is a defect.
- **Unknown record types are tolerated.** `RecordFactory` falls back to `Models::TelemetryRecord` for
  an unrecognized `record_type`, so a newer upstream export never crashes an older miner.
- **Pure and offline.** Read a file, write a file. No network, no subprocess, no global state beyond
  `WildGapMiner.configuration`.
- **Ruby 3.2 floor.** Syntax or stdlib newer than 3.2 breaks the CI matrix and the gemspec.

## What "fail closed" means here

This library has no permission gate to bypass, so failing closed is about honest output.

- Malformed input raises. A missing file, empty content, or invalid JSON raises `ParseError`, and a
  header that fails `ExportHeader#valid?` raises `SchemaError`, producing no report. Note that
  `valid?` is stricter than presence: `export_type` must equal the literal `'session_telemetry'`,
  while `schema_version` and `source_id` need only be non-nil. Flag any change that swallows those
  into a partial or empty report instead.
- Missing evidence produces no gap, never an invented one. When a record type is absent, the analyzer
  emits nothing. It must not substitute a default rate, a zero denominator result, or a placeholder
  action.
- A broad `rescue` is a defect unless the PR argues for it. `rescue => e` or `rescue StandardError`
  that returns `[]` or `nil` converts a real bug into a clean, wrong, empty report. Rescue the
  specific error, re-raise as the typed error from `errors.rb`, and keep the message free of payload
  data.

## Files not to hand-edit

There is little generated content here, so the rule is mostly about what must not appear in the diff:
`Gemfile.lock`, `vendor/bundle/`, `.bundle/`, `pkg/`, `*.gem`, `.rspec_status`, `.beads/`, and
`AGENTS.md` are gitignored on purpose. A library gem does not commit its lockfile. If one of these
shows up in a PR, that is the finding. `lib/wild_gap_miner/version.rb` is the single source of the
gem version, so flag a version asserted in `README.md`, `CHANGELOG.md`, or a spec that disagrees
with it.

## Do not waste comments on

RuboCop territory: line length, `frozen_string_literal` headers, method and block length, `AbcSize`,
parameter counts, naming style, and RSpec style. `.rubocop.yml` is the ruling and CI runs it. Do not
propose adding a gem to solve something stdlib already does, do not ask for type signatures, do not
restate rspec failures CI already prints, and do not re-litigate the archetype B pipeline layout
(ingestion, models, analyzers, scoring, recommendations, report, export). Skip pure documentation
wording preferences unless the doc now contradicts the code.

## Anti-ratchet

On a re-review after new pushes the bar does not rise. Drop findings the update resolved, and do not
invent objections on unchanged lines you previously accepted. Prefer a few high-conviction findings.
If the change is correct, bounded, private, and offline, reply `lgtm`. The reviewer is advisory only
and never blocks a merge.

## Sources

Every claim above about this codebase was opened and read at commit `6864041`, the head of
`ci/minimax-review`. Line numbers are that commit's.

**Repository shape (the opening paragraphs)**

- Offline, no runtime dependencies: `wild-gap-miner.gemspec:1-21` (no `spec.add_dependency`),
  `lib/wild_gap_miner.rb:3-5` (requires `json`, `time`, `tmpdir`, all stdlib)
- No network or subprocess reach: a repo-wide grep of `lib/` for `Net::HTTP`, `URI.open`, `Socket`,
  `ENV[`, `Marshal`, `YAML`, `eval`, `system(`, `%x` returns nothing
- 6 analyzers: `lib/wild_gap_miner/report/builder.rb:8-15`
- JSON or Markdown export: `lib/wild_gap_miner/export/json_exporter.rb:7-16`,
  `lib/wild_gap_miner/export/markdown_exporter.rb:13-30`
- Consumed as a gem: `README.md:24`, `README.md:30`
- Deterministic CI gate: `.github/workflows/ci.yml:14` (matrix `3.2`, `3.3`), `:25` (rspec), `:28`
  (rubocop)

**Authority**

- `CLAUDE.md:82` ("## Upstream Data Contract")
- `000-docs/003-TQ-STND-privacy-model.md`, `000-docs/004-AT-ADEC-architecture-decisions.md`,
  `000-docs/005-DR-REFF-configuration-reference.md` all present

**Defect classes**

1. Detector silently stops detecting: guard-then-`filter_map`-then-`limit_gaps` is the shared shape,
   `lib/wild_gap_miner/analyzers/denial_analyzer.rb:7-13` and `:25`,
   `failure_analyzer.rb:7-13` and `:25`, `latency_analyzer.rb:7-13` and `:26`,
   `utilization_analyzer.rb:7-13` and `:25`, `coverage_analyzer.rb:7-17` and `:30`,
   `pattern_analyzer.rb:7-13` and `:24`. Cap site: `analyzers/base.rb:39-41`
2. Severity bounds: raise at `lib/wild_gap_miner/models/gap.rb:45-47`; aborts the whole report
   because `report/builder.rb:24-33` has no rescue and `ingestion/export_parser.rb:45` is the only
   rescue in `lib/`.
   `clamp_severity` at `analyzers/base.rb:35-37`, `build_gap` at `analyzers/base.rb:24-33`.
   `1.0 - fraction` at `coverage_analyzer.rb:34` and `utilization_analyzer.rb:30`; weighted product
   at `scoring/severity_scorer.rb:16`
3. Analyzer must return `[]`: `Array(...)` wrapping at `denial_analyzer.rb:8`,
   `failure_analyzer.rb:8`, `latency_analyzer.rb:8`, `utilization_analyzer.rb:8`,
   `coverage_analyzer.rb:8-9`, `pattern_analyzer.rb:8`. Division by `all_actions.size` at
   `coverage_analyzer.rb:29`, guarded at `coverage_analyzer.rb:13`
4. Privacy surface: permitted output at `000-docs/003-TQ-STND-privacy-model.md:34-38`; forbidden
   input fields at `:29-30`; the four report-facing fields at `models/gap.rb:8`
5. Untrusted input: the only deserializer is `JSON.parse` at
   `lib/wild_gap_miner/ingestion/export_parser.rb:44`. Templates as the format string with the action
   as an argument: `lib/wild_gap_miner/recommendations/engine.rb:7-20` and `:30`
6. Dependency and reach creep: `wild-gap-miner.gemspec:1-21` (no `add_dependency` anywhere in the
   file), `lib/wild_gap_miner.rb:3-5`
7. Pipeline correctness: percentiles at `analyzers/latency_analyzer.rb:23-42` reading
   `models/latency_stats.rb:11-16`; key shapes at `lib/wild_gap_miner.rb:61` (`merge(header:)`) and
   `report/builder.rb:25-26` (`records[:header]`, `except(:header)`); report shape at
   `models/gap_report.rb:28-35` consumed by `export/json_exporter.rb:8`

**Invariants**

- Severity bounded, type in `VALID_TYPES`: `models/gap.rb:6` (types), `:18` (call site),
  `:40-48` (`validate!`, private, invoked only from `initialize`)
- Analyzers total: contract at `analyzers/base.rb:14-16`, honored by the six guards cited above
- Per-type cap after sorting severity descending: `analyzers/base.rb:39-41` combined with
  `models/gap.rb:32-34`
- Deterministic ordering: `models/gap.rb:32-34` (`<=>` descending), `models/gap_report.rb:10`
  (`gaps.sort` on construction)
- Config validated and freezable: `configuration.rb:44-84` (the seven scalar writers),
  `:86-91` (the `severity_weights=` exception), `:93-96` (`freeze!`), `:100-113` (the validators),
  `:5-13` (`DEFAULTS`)
- Unknown record types tolerated: `ingestion/record_factory.rb:6-13` (dispatch table),
  `:19-23` (fallback to `Models::TelemetryRecord`)
- Pure and offline, one piece of global state: `lib/wild_gap_miner.rb:45-47`
- Ruby 3.2 floor: `wild-gap-miner.gemspec:15`, `.github/workflows/ci.yml:14`, `.ruby-version:1`,
  `.rubocop.yml:5`

**Fail closed**

- Missing file `ingestion/export_parser.rb:16`; empty file `:19`; empty string `:27`; invalid JSON
  `:43-47`; bad header `:49-56` against `models/export_header.rb:18-20`
- Typed error hierarchy: `lib/wild_gap_miner/errors.rb:1-10`
- The single rescue in `lib/` is narrow and re-raises typed: `ingestion/export_parser.rb:45-46`

**Files not to hand-edit**

- `.gitignore:6` (`.beads/`), `:7` (`AGENTS.md`), `:10` (`Gemfile.lock`), `:11` (`vendor/bundle/`),
  `:12` (`.bundle/`), `:13` (`pkg/`), `:14` (`*.gem`), `:17` (`.rspec_status`)
- Single source of the version: `lib/wild_gap_miner/version.rb:4`, consumed at
  `wild-gap-miner.gemspec:7`

**Do not waste comments on**

- `.rubocop.yml:1-11` is the style ruling and `.github/workflows/ci.yml:28` runs it
