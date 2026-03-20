# Changelog

All notable changes to wild-gap-miner are documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.1.0] - 2026-03-20

### Added

#### Epic 1 — Repository Foundation
- Gemspec with `name='wild-gap-miner'`, `authors='Intent Solutions'`, `license='Nonstandard'`, Ruby >= 3.2.0
- Gemfile with RSpec ~> 3.13, RuboCop ~> 1.68, rubocop-rspec ~> 3.2 dev dependencies
- Rakefile with default RSpec task
- `.rspec`, `.ruby-version` (3.2.0), `.rubocop.yml`, `.gitignore`
- CI workflow (`.github/workflows/ci.yml`) with Ruby 3.2 and 3.3 matrix
- Gemini code review workflow (`.github/workflows/gemini-review.yml`)

#### Epic 2 — Error Hierarchy and Configuration
- `WildGapMiner::Error` base and subclasses: `ParseError`, `ValidationError`, `SchemaError`, `ConfigurationError`, `ExportError`
- `WildGapMiner::Configuration` with typed setters, range validation, and `freeze!` support
- Default thresholds: denial 0.2, failure 0.15, latency p95 500ms, utilization min 5, coverage min 0.3, pattern min 3
- Configurable `severity_weights` hash (per gap type) and `max_gaps_per_type` (default 50)
- `WildGapMiner.configure`, `.configuration`, `.reset_configuration!` module-level API

#### Epic 3 — Telemetry Models
- `Models::TelemetryRecord` base class with `record_type` and `raw` accessors
- `Models::ExportHeader` with `valid?` check requiring `export_type`, `schema_version`, `source_id`
- `Models::EventRecord` with outcome predicate methods (`success?`, `denied?`, `error?`, `rate_limited?`)
- `Models::SessionSummary` with `action_count` helper
- `Models::ToolUtilization` with success rate and invocation stats
- `Models::OutcomeDistribution` accepting both `outcomes` (upstream) and `distribution` keys; `percentage_for` method
- `Models::LatencyStats` accepting both `p50_ms`/`p95_ms` (upstream) and bare `p50`/`p95` keys
- `Models::PatternRecord` with `failure_cascade?` predicate; accepts both `unique_callers` and `callers_affected` keys

#### Epic 4 — Ingestion Layer
- `Ingestion::RecordFactory.build` — dispatches raw hash to correct model class
- `Ingestion::ExportParser#parse_file` — parses JSONL file, raises `ParseError` for missing/empty files
- `Ingestion::ExportParser#parse_string` — parses JSONL string, useful for testing
- Returns `{ header: ExportHeader, records: Hash<Symbol, Array<TelemetryRecord>> }`
- Raises `ParseError` for invalid JSON, `SchemaError` for invalid header

#### Epic 5 — Gap Model and Report
- `Models::Gap` with strict type/severity validation, `Comparable` mixin (sorts by severity desc), `to_h`
- `Models::GapReport` with sorted gaps, `summary` stats (total, by_type, severity_avg, high_severity_count, top_actions), `gaps_of_type`, `to_h`

#### Epic 6 — Six Analyzers
- `Analyzers::Base` with `build_gap`, `clamp_severity`, `limit_gaps` helpers
- `Analyzers::DenialAnalyzer` — flags actions with denial rate above threshold
- `Analyzers::FailureAnalyzer` — flags actions with failure rate (1 - success_rate) above threshold
- `Analyzers::LatencyAnalyzer` — flags actions with p95 above threshold; severity scales to 2x threshold
- `Analyzers::UtilizationAnalyzer` — flags actions invoked fewer times than min count
- `Analyzers::CoverageAnalyzer` — flags callers using fewer than min fraction of available actions
- `Analyzers::PatternAnalyzer` — flags patterns meeting min occurrence count; failure cascades get higher base severity

#### Epic 7 — Scoring and Ranking
- `Scoring::SeverityScorer#score` / `#score_all` — applies configurable per-type weight, clamps to [0.0, 1.0]
- `Scoring::PriorityRanker#rank` — returns ranked array with `{rank:, gap:}` entries
- `Scoring::PriorityRanker#sort` — returns gaps sorted by severity descending

#### Epic 8 — Recommendations Engine
- `Recommendations::Engine#enrich` — fills in missing recommendations using per-type templates
- Preserves existing recommendations; templates include action and evidence rate where available

#### Epic 9 — Report Builder and Exporters
- `Report::Builder#build` — orchestrates all 6 analyzers, scoring, and recommendation enrichment
- `Export::JsonExporter#export` / `#write` — serializes `GapReport` to JSON
- `Export::MarkdownExporter#export` / `#write` — renders `GapReport` to human-readable Markdown with severity labels (HIGH/MEDIUM/LOW)

#### Epic 10 — Test Suite and Documentation
- 276 RSpec examples across unit, integration, and adversarial suites, 0 failures
- `spec/support/telemetry_fixtures.rb` — `TelemetryFixtures` module with builder helpers for all record types
- Integration spec covering full parse → analyze → export pipeline
- Adversarial spec covering malformed JSON, invalid configs, nil records, edge cases
- `000-docs/` with 6 documentation files (index, plan, epic build plan, privacy model, architecture decisions, configuration reference, operator guide)
- `CLAUDE.md` with complete repo identity and development instructions
- `README.md` with usage examples, analyzer table, and development commands

[0.1.0]: https://github.com/jeremylongshore/wild-gap-miner/releases/tag/v0.1.0
