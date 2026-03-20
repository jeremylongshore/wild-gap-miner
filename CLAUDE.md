# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in the `wild-gap-miner` repository.

## Identity

- **Repo**: wild-gap-miner
- **Namespace**: WildGapMiner
- **Archetype**: B — Data Pipeline / Analytics
- **Ecosystem**: wild
- **Ecosystem root**: `../CLAUDE.md`
- **Status**: v1 complete — all 10 epics implemented, 276 tests passing, 0 RuboCop offenses

## Mission

Ingest JSON Lines telemetry exports from wild-session-telemetry, run 6 gap analyzers, score and rank gaps, generate recommendations, and export reports in JSON and Markdown.

## Repository Layout

```
lib/wild_gap_miner.rb              # Entry point, require graph, module-level API
lib/wild_gap_miner/
  version.rb                       # VERSION constant
  errors.rb                        # Error hierarchy
  configuration.rb                 # Configuration class with freeze! support
  ingestion/
    export_parser.rb               # JSONL file/string parser
    record_factory.rb              # Builds typed records from raw data
  models/
    export_header.rb               # Export file header
    telemetry_record.rb            # Base record
    event_record.rb                # Tool call events
    session_summary.rb             # Per-caller session summaries
    tool_utilization.rb            # Tool usage stats
    outcome_distribution.rb        # Outcome percentage breakdown
    latency_stats.rb               # p50/p95/p99 latency stats
    pattern_record.rb              # Detected behavioral patterns
    gap.rb                         # Gap value object
    gap_report.rb                  # Report container
  analyzers/
    base.rb                        # Analyzer base class
    denial_analyzer.rb             # High denial rate detection
    failure_analyzer.rb            # High failure rate detection
    latency_analyzer.rb            # High p95 latency detection
    utilization_analyzer.rb        # Low utilization detection
    coverage_analyzer.rb           # Low capability coverage detection
    pattern_analyzer.rb            # Problematic pattern detection
  scoring/
    severity_scorer.rb             # Applies per-type weight adjustments
    priority_ranker.rb             # Sorts and ranks gaps
  recommendations/
    engine.rb                      # Fills in missing recommendations
  report/
    builder.rb                     # Orchestrates full analysis pipeline
  export/
    json_exporter.rb               # Exports GapReport as JSON
    markdown_exporter.rb           # Exports GapReport as Markdown
spec/                              # Mirrors lib/ + integration/ + adversarial/
000-docs/                          # Canonical documentation
planning/                          # Build planning artifacts
```

## Build Commands

```bash
bundle install
bundle exec rspec                  # Run tests (276 examples expected)
bundle exec rubocop                # Lint (0 offenses expected)
```

## Key Design Decisions

- No external runtime dependencies — JSON and Time are stdlib only
- All files have `# frozen_string_literal: true`
- `ExportParser#parse_file` and `#parse_string` return `{ header:, records: }` hashes
- `Report::Builder` expects `records` hash with `:header` key and record-type symbol keys
- `WildGapMiner.analyze(path)` is the convenience entry point
- `Configuration#freeze!` makes config immutable (raises FrozenError on modification)
- `Gap` severity is strictly 0.0–1.0; ValidationError raised otherwise
- Analyzers return `[]` gracefully when relevant records are absent or nil

## Upstream Data Contract

Export source: wild-session-telemetry. First JSONL line is always the header. Record types:
- `event` — individual tool call event
- `session_summary` — per-caller aggregated session data
- `tool_utilization` — per-action invocation and success stats
- `outcome_distribution` — per-action outcome percentages (uses `outcomes` key)
- `latency_stats` — per-action percentile latency (uses `p50_ms`, `p95_ms`, etc.)
- `pattern` — detected behavioral patterns (uses `unique_callers` key)

## Conventions

- RuboCop config in `.rubocop.yml` — `Metrics/ParameterLists Max: 6` accommodates Gap#initialize
- Analyzer `analyze` methods always return `Array<Gap>`, never nil
- All private helper methods in analyzers named `<analyzer>_gap_for`, `<analyzer>_evidence`, etc.
- Tests use `TelemetryFixtures` module (included in spec_helper)
- Integration specs in `spec/integration/`, adversarial specs in `spec/adversarial/`

## Before Working Here

1. Read the ecosystem CLAUDE.md at `../CLAUDE.md`
2. Check `000-docs/` for architecture decisions and configuration reference
3. Run `bundle exec rspec` and `bundle exec rubocop` before and after changes
4. Never commit with failing tests or RuboCop offenses
