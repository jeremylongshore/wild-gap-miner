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
- **Config is validated and freezable.** Every attribute writer calls `check_frozen!`, then a
  `validate_float!` or `validate_integer!` with its documented bounds, before assigning. A new option
  without all three is a defect, as is one that skips `DEFAULTS` or the configuration reference doc.
- **Unknown record types are tolerated.** `RecordFactory` falls back to `Models::TelemetryRecord` for
  an unrecognized `record_type`, so a newer upstream export never crashes an older miner.
- **Pure and offline.** Read a file, write a file. No network, no subprocess, no global state beyond
  `WildGapMiner.configuration`.
- **Ruby 3.2 floor.** Syntax or stdlib newer than 3.2 breaks the CI matrix and the gemspec.

## What "fail closed" means here

This library has no permission gate to bypass, so failing closed is about honest output.

- Malformed input raises. A missing file, empty content, invalid JSON, or a header lacking
  `export_type`, `schema_version`, or `source_id` raises `ParseError` or `SchemaError` and produces
  no report. Flag any change that swallows those into a partial or empty report instead.
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
