# 001-PP-PLAN — Repository Blueprint

**Repo:** wild-gap-miner
**Status:** v1 complete

## Mission

Analyze session telemetry exports from `wild-session-telemetry` to surface capability gaps — what tools struggle, what gets denied, where latency is unacceptable, and what investment is needed.

## Boundaries

### In Scope
- Ingesting JSONL exports from `wild-session-telemetry` schema v1.0
- Six gap analyzer types: denial, failure, latency, utilization, coverage, pattern
- Configurable thresholds, severity weights, and gap caps
- JSON and Markdown report export
- Pure Ruby — no external runtime dependencies

### Out of Scope
- Real-time or streaming telemetry ingestion
- Persistent storage of gaps or historical comparison
- UI or visualization layer
- Direct integration with any LLM or tool registry

## Non-Goals
- Replacing wild-session-telemetry (ingestion is its job)
- Being a general-purpose analytics platform
- Prescriptive remediation — recommendations are advisory

## Stakeholders
- Intent Solutions engineering team
- Operators running AI-assisted workflows who need gap visibility

## Success Criteria
- All 6 analyzers produce correct gaps for well-formed input
- Graceful handling of malformed, missing, or null fields
- Zero external runtime dependencies
- 0 RuboCop offenses, 276+ passing tests
- Reports readable by both machines (JSON) and humans (Markdown)
