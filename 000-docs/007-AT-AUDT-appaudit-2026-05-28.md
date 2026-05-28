# 007-AT-AUDT — Operator-Grade System Audit (wild-gap-miner)

**Document type:** Architecture audit
**Filed as:** `007-AT-AUDT-appaudit-2026-05-28.md`
**Repo:** `wild-gap-miner` (v1 — 276 specs, 0 RuboCop offenses)
**Audit date:** 2026-05-28
**Audience:** senior Rails/Ruby engineer, first read, 10 min to operate
**Author:** Operator-grade automated audit

---

## 1. Mission & Boundaries

`wild-gap-miner` is the **analytics terminus** of the wild ecosystem's observability triad:
`wild-admin-tools-mcp` → `wild-session-telemetry` → **`wild-gap-miner`**. It is a pure Ruby
library gem (Ruby 3.2+, stdlib-only — `json`, `time`, `tmpdir`) that ingests JSON Lines
telemetry exports, runs six independent analyzers, scores findings, ranks them, attaches
human-readable recommendations, and emits a `GapReport` rendered as JSON or Markdown. There
is no daemon, no HTTP endpoint, no persistence, and no MCP server. One call in
(`WildGapMiner.analyze(path)`), one report object out.

**What "gap analysis" means here.** A gap is one of six measurable signals that a capability
in the underlying agent surface is either over-claimed, under-used, or operating below the
expected quality bar. The six gap types are enumerated in `Models::Gap::VALID_TYPES`
(`lib/wild_gap_miner/models/gap.rb:6`): `denial`, `failure`, `latency`, `utilization`,
`coverage`, `pattern`. Every gap carries a `type`, an `action` (the tool/operation name or
caller ID it applies to), a `severity ∈ [0.0, 1.0]`, an `evidence` hash for forensic
review, a `description` for human consumers, and an optional `recommendation` string.

**In scope.**

- Parsing a single JSON Lines export from `wild-session-telemetry` (header line + N typed records).
- Running the six analyzers over the parsed record set.
- Per-type severity weighting via `severity_weights` configuration.
- Capping gaps per analyzer via `max_gaps_per_type`.
- Generating recommendation strings via a template engine when an analyzer leaves the field nil.
- Rendering the assembled `GapReport` as JSON or Markdown.

**Out of scope.**

- **Transcript analysis.** Despite the ecosystem CLAUDE.md naming `wild-transcript-pipeline` as
  an upstream producer for gap-miner, no transcript ingestion code exists in this repo. See
  Section 4 for the full asymmetry.
- Live event streaming (only batch JSONL).
- Persistence — `GapReport` lives in memory; export writes are one-shot file writes.
- Cross-export trend analysis. Every run is a single export, single report.
- Remediation execution. Recommendations are advisory strings, not machine-actionable codes
  (architecture decision AD-007).
- Privacy filtering. Gap-miner assumes the producer has already enforced privacy guarantees
  per `wild-session-telemetry/000-docs/003-TQ-STND-privacy-model.md`.

The mission statement in `CLAUDE.md` is consistent with the code: "Ingest JSONL telemetry,
run 6 analyzers, score, rank, recommend, export." There is no scope creep.

---

## 2. Analysis Architecture

The codebase is 1,120 lines of Ruby across 25 production files. The dependency flow is
deliberate and one-directional — there are no circular `require_relative` chains, and the
analyzers do not know about each other.

```
+---------------------------+
|  WildGapMiner.analyze     |   lib/wild_gap_miner.rb:58
|  (module-level entry)     |
+-------------+-------------+
              |
              v
+---------------------------+      +-----------------------------+
| Ingestion::ExportParser   |----->| Ingestion::RecordFactory    |
| parse_file / parse_string |      | RECORD_TYPE_MAP -> Models   |
+-------------+-------------+      +-----------------------------+
              |
              v
        { header:, records: }   (records is Hash<Symbol, Array<Models::*>>)
              |
              v
+---------------------------+
| Report::Builder           |   lib/wild_gap_miner/report/builder.rb
|  - run_analyzers          |
|  - score (SeverityScorer) |
|  - enrich (RecsEngine)    |
+-------------+-------------+
              |
              v
         Models::GapReport
              |
       +------+------+
       v             v
  JsonExporter   MarkdownExporter
```

**Layer responsibilities (with file references).**

| Layer | File(s) | Responsibility |
|-------|---------|----------------|
| Entry point | `lib/wild_gap_miner.rb` | Module-level `analyze`, `configure`, `reset_configuration!` |
| Configuration | `lib/wild_gap_miner/configuration.rb` | Thresholds, weights, validation, `freeze!` lockdown |
| Ingestion | `lib/wild_gap_miner/ingestion/export_parser.rb` | Read JSONL, separate header from records |
| Record factory | `lib/wild_gap_miner/ingestion/record_factory.rb` | Map `record_type` string → concrete `Models::*` class |
| Models | `lib/wild_gap_miner/models/*.rb` | Immutable value objects for each record type + `Gap` + `GapReport` |
| Analyzers | `lib/wild_gap_miner/analyzers/*.rb` | Six independent gap detectors, all inheriting from `Base` |
| Scoring | `lib/wild_gap_miner/scoring/severity_scorer.rb` + `priority_ranker.rb` | Apply per-type weight; produce ranked output |
| Recommendations | `lib/wild_gap_miner/recommendations/engine.rb` | Fill missing `recommendation` field from templates |
| Orchestration | `lib/wild_gap_miner/report/builder.rb` | Compose all stages into a `GapReport` |
| Export | `lib/wild_gap_miner/export/{json,markdown}_exporter.rb` | Serialize `GapReport.to_h` |

**The analyzer family.** All six analyzers inherit from `Analyzers::Base`
(`lib/wild_gap_miner/analyzers/base.rb`), which provides `build_gap`, `clamp_severity`, and
`limit_gaps`. Each subclass implements two protected hooks: `gap_type` (a symbol) and a
private `<name>_gap_for(record)` method that returns a `Gap` or `nil`. The `analyze`
method is a `filter_map { ... }` over the relevant record array, followed by
`limit_gaps` to cap output at `config.max_gaps_per_type`. This is a textbook strategy
pattern — each analyzer is independently testable, independently disable-able (in theory;
see Section 8 for the absence of an enable/disable knob), and adds no shared state.

The `Builder` orchestration (`lib/wild_gap_miner/report/builder.rb:8-15`) hard-codes the
six analyzer classes in a frozen array. Adding a seventh analyzer requires editing this
constant — there is no registry pattern. That is fine for v1 but is the right wire to pull
for v2 plugin extensibility (Section 9).

**Severity is normalized once, weighted once, never re-clamped after weighting bug-out.**
The flow is: analyzer produces `Gap` with severity in `[0.0, 1.0]` (clamped internally),
`SeverityScorer#score` multiplies by the configured weight and re-clamps to `[0.0, 1.0]`,
and `Recommendations::Engine#enrich` preserves severity exactly. The `Gap#initialize`
validator (`lib/wild_gap_miner/models/gap.rb:40-48`) is the load-bearing guarantee — every
scoring or enrichment step that produces a new `Gap` will fault loudly if severity escapes
the unit interval.

---

## 3. The Critical Path

A complete telemetry batch from disk to ranked report passes through fifteen distinct
method calls. Reading the code top-to-bottom for the first time, this is the path to trace.

1. **Entry.** Caller invokes `WildGapMiner.analyze('/tmp/telemetry.jsonl')`
   (`lib/wild_gap_miner.rb:58`).
2. **Configuration resolution.** The default `Configuration` instance is fetched via the
   memoized class-level accessor (`lib/wild_gap_miner.rb:45`). If frozen, all subsequent
   writes raise `FrozenError`.
3. **Parser construction.** `Ingestion::ExportParser.new(config: config)`
   (`lib/wild_gap_miner/ingestion/export_parser.rb:8`).
4. **File read.** `parse_file` checks existence (raises `ParseError` if missing), reads all
   lines, strips empties (raises `ParseError` if the file is empty post-strip).
5. **Header parsing.** `parse_lines` calls `parse_json` on line 1, then `build_header`.
   `Models::ExportHeader#valid?` enforces `export_type == 'session_telemetry'` AND
   non-nil `schema_version` AND non-nil `source_id` — anything else raises `SchemaError`
   (`lib/wild_gap_miner/ingestion/export_parser.rb:51-52`).
6. **Record building loop.** Lines 2…N are parsed one at a time. Each parsed hash is passed
   to `RecordFactory.build(data)`, which looks up `data['record_type']` in `RECORD_TYPE_MAP`
   and instantiates the matching `Models::*` class. Unknown types fall through to the bare
   `TelemetryRecord` superclass (`lib/wild_gap_miner/ingestion/record_factory.rb:15-24`).
7. **Records bucket.** Records are pushed into a `Hash` keyed by `record_type.to_sym`,
   with a `Hash.new { |h, k| h[k] = [] }` default to keep absent buckets as empty arrays.
8. **Builder construction.** Back in `WildGapMiner.analyze` (`lib/wild_gap_miner.rb:61`),
   the parsed records are merged with the header under the key `:header`. `Report::Builder`
   then separates that out via `records.except(:header)` (line 26 of `builder.rb`).
9. **Analyzer fan-out.** `Builder#run_analyzers` does
   `ANALYZERS.flat_map { |k| k.new(config:).analyze(typed_records) }`. Each analyzer reads
   only the record arrays it cares about (e.g., `DenialAnalyzer` looks at
   `records[:outcome_distribution]`).
10. **Gap construction.** Inside each analyzer, `filter_map` builds `Gap` instances via the
    `Base#build_gap` helper. Severities are clamped at construction.
11. **Per-type capping.** `Base#limit_gaps` sorts descending by severity and keeps the top
    `max_gaps_per_type`.
12. **Scoring.** `Builder#score` calls `Scoring::SeverityScorer#score_all`, which produces a
    new `Gap` for each input with severity multiplied by `severity_weights.fetch(type, 1.0)`
    and re-clamped.
13. **Enrichment.** `Builder#enrich` calls `Recommendations::Engine#enrich`. Any `Gap` with a
    nil recommendation is rebuilt with a template-filled string.
14. **Report construction.** `Models::GapReport.new(header:, gaps:)` sorts gaps by severity
    descending (`Gap#<=>` is inverted) and stamps `generated_at` with the current UTC ISO8601.
15. **Return.** The caller now holds a `GapReport` with `summary`, `gaps_of_type`, and `to_h`
    available for downstream rendering.

End-to-end on the 276-test suite: under 200 ms cold. The library is I/O-bound on the
`File.readlines` call; the analyzers themselves are linear scans with no nested joins.

---

## 4. Data Contracts (Inputs)

Gap-miner depends on **one** producer contract today, despite the ecosystem CLAUDE.md
naming **two**. The asymmetries documented below are the most important findings in this
audit.

### 4.1 From `wild-session-telemetry`

Gap-miner expects the JSON Lines format defined in
`../wild-session-telemetry/000-docs/004-AT-STND-data-contracts.md`. The parser reads line 1
as the header and lines 2…N as typed records. The accepted record types are wired in
`lib/wild_gap_miner/ingestion/record_factory.rb:6-13`:

```ruby
RECORD_TYPE_MAP = {
  'event'                 => Models::EventRecord,
  'session_summary'       => Models::SessionSummary,
  'tool_utilization'      => Models::ToolUtilization,
  'outcome_distribution'  => Models::OutcomeDistribution,
  'latency_stats'         => Models::LatencyStats,
  'pattern'               => Models::PatternRecord
}.freeze
```

The record-type set matches the producer contract. However, several **field-level**
asymmetries exist between what gap-miner parses and what the producer actually emits:

| # | Field | Producer doc says | Producer **code** emits | Gap-miner reads | Severity |
|---|-------|-------------------|-------------------------|------------------|----------|
| 1 | Header `source_id` | Required (doc 004 §4.2) | **Not emitted** (`RecordBuilder#header`, `Exporter#build_header` — `wild-session-telemetry/lib/.../export/{record_builder,exporter}.rb`) | **Required** (`ExportHeader#valid?` → raises `SchemaError` if nil) | **CRITICAL** |
| 2 | `outcome_distribution.outcomes` | `{ outcome_name => { count, percentage } }` (doc §4.3) | `{ outcome_name => { count:, percentage: } }` (Engine line 45-49) | Treated as `{ outcome_name => Float }` (`OutcomeDistribution#percentage_for`) | **CRITICAL** |
| 3 | `latency_stats` numeric keys | `p50_ms`, `p95_ms`, `p99_ms`, `min_ms`, `max_ms`, `avg_ms` (doc §4.3) | `p50`, `p95`, `p99`, `min`, `max`, `avg` (bare, Engine line 89-90) | Accepts both (`LatencyStats#ms_field`, AD-006) | Tolerated by design |
| 4 | `outcome_distribution` key name | `outcomes` | `outcomes` | `distribution` OR `outcomes` (with `outcomes` fallback) | Tolerated |
| 5 | Pattern caller count key | `unique_callers` | `unique_callers` | `unique_callers` OR `callers_affected` | Aligned |
| 6 | `session_summary` window bounds | `window_start`, `window_end` (doc §4.3) | Emitted | **Not read** (`SessionSummary` ignores both) | Information loss |

**Asymmetry #1 — missing `source_id`.** Doc 004 §4.2 lists `source_id` as a required header
field, and gap-miner's `ExportHeader#valid?` enforces it. But the producer's
`Export::RecordBuilder#header` method (lines 9-17) and `Export::Exporter#build_header`
(lines 58-70) build a header **with no `source_id` field at all**. The header keyword
arguments are `schema_version`, `exported_at`, `time_range`, `record_counts` — and
nothing else. **Every export produced by the live exporter today will be rejected by
gap-miner with `SchemaError: export header missing required fields`.** Tests pass on both
sides because each repo's fixtures inject what its own code expects. This is a contract
drift that no spec catches.

**Asymmetry #2 — outcome distribution shape mismatch.** The producer's `Aggregation::Engine#outcome_distributions`
(line 45-49) emits each outcome as a nested hash: `{ success: { count: 144, percentage: 0.923 }, ... }`.
Gap-miner's `Models::OutcomeDistribution#percentage_for(outcome)` returns
`distribution[outcome.to_s] || 0.0` (line 14) and `DenialAnalyzer#denial_gap_for` immediately
compares the return value against `config.denial_threshold` with `<` (line 25 of
`denial_analyzer.rb`). On real producer output, that comparison is `Hash < Float`, which
raises `ArgumentError: comparison of Hash with Float failed`. Again, tests pass because
the test fixture (`spec/support/telemetry_fixtures.rb:46`) uses the flat form
`'outcomes' => { 'success' => 0.8 }` — which is **not** what the live producer emits.

**Asymmetry #3 — latency keys.** Producer emits bare `p50/p95/...`; doc says
`p50_ms/p95_ms/...`. Gap-miner is correctly defensive — `LatencyStats#ms_field` (line 23-25
of `latency_stats.rb`) accepts both forms. AD-006 calls this out explicitly. No action
required, but it is the only documented case where the gap-miner author noticed and
defended against an upstream drift.

**Asymmetry #6 — dropped window bounds.** Session summary records arrive with
`window_start`/`window_end`, but `SessionSummary#initialize` reads only `caller_id`,
`event_count`, `distinct_actions`, `outcome_breakdown`, `total_duration_ms`. The window
bounds are dropped. This is not a bug — it is unused capacity — but it forecloses any
"gap per time window" feature in v2 without re-parsing.

### 4.2 From `wild-transcript-pipeline`

**Gap-miner does not consume transcript data.** Zero references to `transcript`, `intent`,
or `tool_reference` exist anywhere in `lib/` or `spec/`. However:

- The wild ecosystem `CLAUDE.md` (Section 2 table) lists gap-miner's role as "gap analysis
  from telemetry **and transcript data**."
- The wild-transcript-pipeline contract doc 005 §"Downstream Consumer Contract" says
  "Gap-miner expects `transcripts[].turns` to contain redacted content … `transcripts[].intents`
  for gap detection … `transcripts[].tool_references` where `action=:not_found` signals a gap."

The transcript-pipeline doc is making a unilateral claim about gap-miner that the
gap-miner code does not honor. Either the ecosystem mission is wrong (gap-miner is
telemetry-only) or gap-miner is missing a planned v2 feature. The codebase currently makes
gap-miner telemetry-only; the ecosystem and transcript-pipeline docs need to be aligned
to reality, or a v2 epic needs to add a transcript ingestion path.

---

## 5. Gap Taxonomy

The six gap types are enumerated in `Models::Gap::VALID_TYPES`
(`lib/wild_gap_miner/models/gap.rb:6`) and individually owned by the analyzer files in
`lib/wild_gap_miner/analyzers/`. Each analyzer reads exactly one record-type bucket and
emits gaps of exactly one type.

| Gap type | Owner | Reads | Triggered when | Severity formula |
|----------|-------|-------|----------------|------------------|
| `denial` | `DenialAnalyzer` | `outcome_distribution` | `percentage_for('denied') >= denial_threshold` (default 0.20) | `clamp(denial_rate, 0..1)` |
| `failure` | `FailureAnalyzer` | `tool_utilization` | `(1.0 - success_rate) >= failure_threshold` (default 0.15) | `clamp(failure_rate, 0..1)` |
| `latency` | `LatencyAnalyzer` | `latency_stats` | `p95 > latency_p95_threshold_ms` (default 500.0) | `clamp((p95/threshold capped at 2) - 1, 0..1)` |
| `utilization` | `UtilizationAnalyzer` | `tool_utilization` | `invocation_count < utilization_min_count` (default 5) | `clamp(1 - count/min, 0..1)` |
| `coverage` | `CoverageAnalyzer` | `session_summary` + `tool_utilization` | per-caller `(distinct_actions ∩ all_actions) / all_actions < coverage_min_fraction` (default 0.30) | `clamp(1 - fraction, 0..1)` |
| `pattern` | `PatternAnalyzer` | `pattern` | `occurrence_count >= pattern_min_occurrences` (default 3) | `0.6` (cascade) or `0.3` (non-cascade) + `min(count/50, 0.4)` |

Severity-to-label mapping (`Export::MarkdownExporter::SEVERITY_LABELS`,
`lib/wild_gap_miner/export/markdown_exporter.rb:5-9`): `>= 0.7` HIGH, `>= 0.4` MEDIUM,
otherwise LOW. The operator guide (doc 006 §"Interpreting Severity Levels") matches.

The taxonomy is **closed** — `Models::Gap#validate!` rejects any type not in `VALID_TYPES`.
Adding a seventh gap type requires editing two files (the enum and the `Builder::ANALYZERS`
constant) plus shipping a new analyzer.

---

## 6. Failure Modes & Blast Radius

The library is single-process, in-memory, no network, no persistence. The blast radius of
any single failure is the caller's process, and the recovery is "fix the input or the
config and re-run." That makes the failure-mode catalogue narrow but worth enumerating.

| Failure | Where it surfaces | Behavior | Blast radius | Mitigation |
|---------|-------------------|----------|---------------|------------|
| File not found | `ExportParser#parse_file:16` | Raises `ParseError` | Caller process | Caller catches per doc 006 §"Error Handling" |
| Empty file | `ExportParser#parse_file:19` | Raises `ParseError` | Caller process | Same |
| Malformed JSON on any line | `ExportParser#parse_json:46` | Raises `ParseError` with line number | Whole batch aborted | Same — partial-batch ingestion is not supported |
| Header missing `export_type`, `schema_version`, or `source_id` | `ExportHeader#valid?` → `ExportParser#build_header:52` | Raises `SchemaError` | Whole batch aborted | **Affected by Asymmetry #1** — currently fires on every live producer export |
| Unknown `record_type` | `RecordFactory.build:21-22` | Falls through to bare `TelemetryRecord` | Silent — record is grouped under its own symbol bucket, no analyzer reads it | None needed |
| Record missing optional fields | All `Models::*` constructors use `\|\| default` | Defaults to 0, [], or {} | None — analyzer thresholds will see zero values | Verified by adversarial spec line 32-43 |
| Hash where a Float is expected (Asymmetry #2) | `DenialAnalyzer:25` (and elsewhere on real producer data) | Raises `ArgumentError: comparison of Hash with Float failed` | Whole batch aborted | **No defense currently. Add a shape assertion in `OutcomeDistribution`.** |
| Classifier collapse (everything flagged) | Producible by misconfig: `denial_threshold = 0.0`, `utilization_min_count = 999999`, `coverage_min_fraction = 1.0` | Every record becomes a gap, then `max_gaps_per_type` truncates | Memory bounded (max 50 × 6 = 300 gaps by default); report becomes useless but doesn't OOM | `max_gaps_per_type` is the floor; operator playbook needs to add a sanity-check pass |
| Invalid `Gap` severity (>1.0 or <0.0) | `Gap#validate!:45-47` | Raises `ValidationError` | Whole batch aborted | Should only fire on developer error — `clamp_severity` and `SeverityScorer#score` both clamp |
| Invalid configuration value | `Configuration#validate_*!` | Raises `ConfigurationError` | Configuration write rejected; previous value preserved | Documented per-key in `005-DR-REFF` |
| Frozen-config mutation | `Configuration#check_frozen!:101` | Raises `FrozenError` | Configuration write rejected | Intentional after `freeze!` |
| Report serialization failure | `JSON.generate` in `JsonExporter#export` | Raises whatever `JSON` raises (typically `JSON::GeneratorError` if a non-serializable object made it into evidence) | Export aborted; report intact in memory | None — evidence hashes today are all primitives, so this is theoretical |
| `File.write` failure in either exporter | `JsonExporter#write:13` / `MarkdownExporter#write:24` | Raises `Errno::*` | Export aborted | Caller's responsibility |

**The single most likely real-world failure** is Asymmetry #1: a fresh integration with
the live producer will fault on the first export because the header lacks `source_id`.
The second-most-likely is Asymmetry #2 firing once the first asymmetry is patched. Both
are catchable by adding integration fixtures that round-trip through the **real
producer's** `RecordBuilder` instead of through a hand-rolled hash.

---

## 7. Trade-Off Analysis

Three meaningful trade-offs were made by the v1 author. Each is defensible; each has a
cost.

**Trade-off 1: Stdlib-only, zero runtime dependencies (AD-001).**

The decision (per `000-docs/004-AT-ADEC` AD-001) is to use only `json`, `time`, `tmpdir`
from stdlib. The benefit is real: zero dependency surface means no version conflicts when
embedded in another tool, no `bundle install` minefield, no transitive CVE exposure. The
cost is also real: no `ActiveSupport::HashWithIndifferentAccess` means every model reaches
into `data['key']` (string keys) by hand; no `dry-validation` means every shape check is
hand-rolled in the `Configuration#validate_*!` helpers; no `oj` means JSON parse/generate
runs on the slower stdlib path. For a library that processes a single batch in under 200
ms, the speed cost is negligible. For a future v2 that wants schema-driven validation of
input records (Section 9), the absence of `dry-schema` or equivalent will be felt.

**Verdict:** Correct call for v1. Re-evaluate if record validation becomes a v2 feature.

**Trade-off 2: Hard-coded analyzer list in `Builder::ANALYZERS`.**

The orchestration class enumerates the six analyzers in a frozen array
(`lib/wild_gap_miner/report/builder.rb:8-15`). Adding a new analyzer is a two-line edit (plus
the analyzer file and its tests). The alternative would be a registry pattern —
`Analyzers.register(MyAnalyzer)` populating a class-level hash — which would let third
parties or sibling repos plug in custom analyzers without forking gap-miner.

The trade-off: registry patterns add a class-level mutable state surface (the registry
itself), which conflicts with AD-003's "analyzers are stateless and independently
instantiable" principle. The hard-coded list keeps the analyzer set knowable from a single
file; nobody can monkey-patch a fourth analyzer in.

**Verdict:** Defensible for a v1 library distributed as a gem. A plugin host (v2) would
want the registry.

**Trade-off 3: Recommendations are advisory strings, not structured codes (AD-007).**

The `Recommendations::Engine` produces a free-text string per gap. There is no
machine-readable code, no link to a remediation script, no severity-of-recommendation
metadata. The trade-off the author identified (per AD-007): structured codes would require
a coordination contract with other wild repos that don't exist yet.

The cost: today's recommendations are useful for a human reading a Markdown report and
worthless for any automated remediation pipeline. A `gap.recommendation_code = :tune_permission_grants`
would let a downstream tool act, but defining the code namespace is a cross-repo conversation
that gap-miner can't have alone.

**Verdict:** Correct sequencing — ship the human path first, defer the machine path until
a consumer exists. The v2 successor is the `wild-skillops-registry` repo named in the
ecosystem CLAUDE.md table; that is the natural place for the recommendation-code namespace
to be owned.

**Honorable mention — the `severity_weights` design.** The weights default to 1.0 per
type, are applied multiplicatively after raw severity, and re-clamp to `[0, 1]`. This
makes the weight a "boost" knob, not a "weight" in the linear-model sense — a 2.0 weight
on a 0.6 severity gap pegs it at 1.0 (HIGH), but a 2.0 weight on a 0.3 severity gap
becomes 0.6 (MEDIUM), not 0.6 + some baseline. Operators tuning weights will need to
internalize that the relationship is `min(1.0, severity * weight)`, not anything more
exotic. The doc 006 example "denial gap at 0.5 with weight 1.5 becomes 0.75 (HIGH)" is
consistent with the code but understates how aggressively the clamp truncates near 1.0.

---

## 8. Operator Playbook

This is the 5-minute path from a fresh checkout to a usable Markdown report. Everything
here is verified against the v1 code.

**Sanity check the install.**

```bash
cd ~/000-projects/wild/wild-gap-miner
bundle install
bundle exec rspec       # expect: 276 examples, 0 failures
bundle exec rubocop     # expect: 0 offenses
```

**Obtain a telemetry export.** See `wild-session-telemetry/000-docs/010-OD-GUID-operator-workflow-guide.md`
for the producer side. **Verify the export header has a `source_id` field** before
running gap-miner — if it does not (today's producer code path does not emit one — see
Section 4 Asymmetry #1), inject one manually:

```bash
jq -c 'if .export_type == "session_telemetry" and (.source_id // null) == null then . + {source_id: "manual-injected"} else . end' \
  /tmp/telemetry.jsonl | head -1 > /tmp/header-fixed.jsonl
tail -n +2 /tmp/telemetry.jsonl >> /tmp/header-fixed.jsonl
```

**Run a mining batch.** From a Ruby process or `bin/console`:

```ruby
require 'wild_gap_miner'

WildGapMiner.configure do |c|
  c.denial_threshold         = 0.15
  c.failure_threshold        = 0.10
  c.latency_p95_threshold_ms = 300.0
  c.utilization_min_count    = 10
  c.coverage_min_fraction    = 0.25
  c.pattern_min_occurrences  = 5
  c.severity_weights         = { denial: 1.5, failure: 1.3 }
end
WildGapMiner.configuration.freeze!

report = WildGapMiner.analyze('/tmp/header-fixed.jsonl')
puts report.summary
```

**Inspect classified gaps.**

```ruby
report.gaps_of_type(:denial).each do |gap|
  puts "[#{gap.severity.round(2)}] #{gap.action}"
  puts "  evidence: #{gap.evidence.inspect}"
  puts "  rec: #{gap.recommendation}"
end
```

`gap.evidence` always carries the threshold that fired, the observed value, and the
sample size — that is the forensic trail for "why did this gap fire?".

**Tune thresholds in response.** If everything is flagged HIGH, the thresholds are too
permissive for your environment. The defaults in `Configuration::DEFAULTS`
(`lib/wild_gap_miner/configuration.rb:5-13`) are conservative and intended for unknown
workloads. Tighten by lowering `denial_threshold` (more denials flagged) or raising
`utilization_min_count` (fewer "low utilization" false positives). For coverage tuning,
start at 0.10 and walk up — coverage gaps are noisy on systems with many narrowly-scoped
service accounts.

**Recover from a `SchemaError` on first contact.** If the parser raises
`SchemaError: export header missing required fields`, your producer's exporter is
emitting a header without `source_id`. Patch the header inline (see jq snippet above) or
patch the producer's `Export::RecordBuilder#header`. Filing a bug against the producer is
the right long-term move — Section 9 recommends it.

**Recover from a `Hash < Float` `ArgumentError`.** This means the producer emitted the
nested-`{count, percentage}` form of `outcome_distribution.outcomes`. Today gap-miner does
not know how to read that shape. Until v2 lands a parser fix, transform the export:

```bash
jq -c 'if .record_type == "outcome_distribution" then .outcomes |= map_values(.percentage) else . end' \
  /tmp/telemetry.jsonl > /tmp/flat.jsonl
```

**Export the report.**

```ruby
WildGapMiner::Export::MarkdownExporter.new.write(report, '/tmp/gaps.md')
WildGapMiner::Export::JsonExporter.new.write(report,     '/tmp/gaps.json')
```

---

## 9. Recommendations for v2

These are the honest, code-grounded improvements. The two contract bugs at the top should
ship as a patch release; the rest are real v2 work.

**Ship as v1.0.1 (bug-fix patch):**

1. **Fix Asymmetry #1.** Either patch the producer's `Export::RecordBuilder#header` to
   emit `source_id` (preferred — the contract doc already says it's required) or relax
   `Models::ExportHeader#valid?` to make `source_id` optional with a logged warning. File
   a bead in `wild-session-telemetry`; coordinate the fix on both sides. **This is the
   #1 priority — the live integration is broken today.**

2. **Fix Asymmetry #2.** Teach `Models::OutcomeDistribution` to handle both the flat
   (`{success: 0.8}`) and nested (`{success: {count:, percentage:}}`) shapes —
   `percentage_for` becomes "if value is Hash, return `value[:percentage]`; else return
   the value." Add a round-trip integration spec that builds an export via the **real**
   `wild-session-telemetry` exporter (via the gem, not a hand-rolled fixture) and feeds
   it to gap-miner.

3. **Add a producer-real fixture.** The single highest-leverage spec to add is one that
   wires `wild-session-telemetry`'s real `Exporter` to gap-miner's real `ExportParser` and
   asserts the pipeline runs. This would have caught both Asymmetry #1 and #2 on day one.

**Real v2 work:**

4. **Resolve the transcript-pipeline contract conflict.** Either (a) implement transcript
   ingestion (new `Ingestion::TranscriptParser`, new `TranscriptRecord` models, new
   analyzers for `intent` and `tool_references[].action=:not_found` gaps) and ship a
   coherent telemetry+transcript pipeline, or (b) delete the transcript-pipeline doc's
   "Downstream Consumer Contract (wild-gap-miner)" section and amend the ecosystem
   CLAUDE.md to call gap-miner telemetry-only. The current state is documentation drift
   that will cost a future engineer a half-day of confusion.

5. **Analyzer registry.** Replace `Builder::ANALYZERS = [...]` with a registry that
   sibling repos can extend. Pair with a stable `Analyzers::Base` API contract documented
   in 000-docs so plugin authors know what they're committing to.

6. **Structured recommendation codes.** When `wild-skillops-registry` lands, define the
   recommendation-code namespace there and add an optional `recommendation_code:` field
   to `Models::Gap`. Keep the free-text recommendation for human consumers.

7. **Window-aware analysis.** Stop dropping `session_summary.window_start` /
   `window_end` (Asymmetry #6) and let analyzers emit per-window gaps. Enables trend
   detection without re-architecting.

---

## Appendix: File Inventory

```
lib/wild_gap_miner.rb                                    (65 lines, entry point)
lib/wild_gap_miner/version.rb                            (<10, VERSION constant)
lib/wild_gap_miner/errors.rb                             (10, error hierarchy)
lib/wild_gap_miner/configuration.rb                      (115, thresholds + freeze!)
lib/wild_gap_miner/ingestion/export_parser.rb            (71, JSONL parser)
lib/wild_gap_miner/ingestion/record_factory.rb           (27, type dispatch)
lib/wild_gap_miner/models/{export_header,event_record,session_summary,
  tool_utilization,outcome_distribution,latency_stats,
  pattern_record,telemetry_record,gap,gap_report}.rb     (~340 total)
lib/wild_gap_miner/analyzers/{base,denial,failure,latency,
  utilization,coverage,pattern}_analyzer.rb              (~390 total)
lib/wild_gap_miner/scoring/{severity_scorer,
  priority_ranker}.rb                                    (~53 total)
lib/wild_gap_miner/recommendations/engine.rb             (53)
lib/wild_gap_miner/report/builder.rb                     (52)
lib/wild_gap_miner/export/{json,markdown}_exporter.rb    (131 total)
```

Total: 1,120 production LOC. 276 specs, 0 RuboCop offenses. Zero runtime gem dependencies.
