# 002-PP-PLAN — Epic Build Plan

**Repo:** wild-gap-miner
**Status:** All 10 epics complete — v0.1.0

## Epic Overview

| Epic | Title | Status |
|------|-------|--------|
| E1 | Repository Foundation | Complete |
| E2 | Error Hierarchy and Configuration | Complete |
| E3 | Telemetry Models | Complete |
| E4 | Ingestion Layer | Complete |
| E5 | Gap Model and Report | Complete |
| E6 | Six Analyzers | Complete |
| E7 | Scoring and Ranking | Complete |
| E8 | Recommendations Engine | Complete |
| E9 | Report Builder and Exporters | Complete |
| E10 | Test Suite and Documentation | Complete |

## E1 — Repository Foundation
Gemspec, Gemfile, Rakefile, CI workflow, dotfiles (.rspec, .rubocop.yml, .ruby-version, .gitignore).

## E2 — Error Hierarchy and Configuration
Error classes (ParseError, ValidationError, SchemaError, ConfigurationError, ExportError).
Configuration class with typed setters, validation, freeze! support, and sensible defaults.

## E3 — Telemetry Models
ExportHeader, TelemetryRecord base, EventRecord, SessionSummary, ToolUtilization,
OutcomeDistribution, LatencyStats, PatternRecord. All support the upstream data contract
with field aliasing for schema compatibility.

## E4 — Ingestion Layer
RecordFactory dispatches raw hashes to typed models. ExportParser handles both file and string
input, validates the header, and groups records by type.

## E5 — Gap Model and Report
Gap is an immutable value object with type/severity validation and Comparable support.
GapReport holds sorted gaps with summary stats and type-filtered accessors.

## E6 — Six Analyzers
All analyzers extend Base and implement #analyze(records) returning Array<Gap>.
Each extracts private helper methods to stay within AbcSize and MethodLength limits.
Nil-safe via Array() wrapping.

## E7 — Scoring and Ranking
SeverityScorer applies per-type weights from config, clamping result to [0.0, 1.0].
PriorityRanker sorts by severity and assigns integer ranks.

## E8 — Recommendations Engine
Engine#enrich fills in missing recommendations from per-type templates.
Existing recommendations are always preserved.

## E9 — Report Builder and Exporters
Builder orchestrates analyzers, scorer, and engine in sequence.
JsonExporter serializes to JSON via stdlib. MarkdownExporter renders human-readable report
with severity labels (HIGH/MEDIUM/LOW) and evidence tables.

## E10 — Test Suite and Documentation
276 RSpec examples across unit, integration, and adversarial suites.
TelemetryFixtures support module. Documentation in 000-docs/.
CLAUDE.md, README.md, CHANGELOG.md authored.
