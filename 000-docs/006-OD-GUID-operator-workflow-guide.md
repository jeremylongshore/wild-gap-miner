# 006-OD-GUID — Operator Workflow Guide

**Repo:** wild-gap-miner
**Status:** v1

## Overview

This guide covers the end-to-end workflow for running gap analysis in production environments:
obtaining an export from `wild-session-telemetry`, configuring and running `wild-gap-miner`, and
routing the resulting reports.

---

## Step 1: Obtain a Telemetry Export

Use `wild-session-telemetry` to export a session window as JSONL:

```bash
# Example using wild-session-telemetry CLI (see its docs for exact flags)
wst export --from 2025-01-14 --to 2025-01-15 --output /tmp/telemetry.jsonl
```

Verify the export:
- First line must be a valid JSON header with `export_type: "session_telemetry"`
- Subsequent lines are typed records

---

## Step 2: Configure Thresholds for Your Environment

Default thresholds are conservative. Tune them to match your expected baseline:

```ruby
WildGapMiner.configure do |c|
  # High-traffic production: tighten denial tolerance
  c.denial_threshold         = 0.10
  c.failure_threshold        = 0.08

  # Fast SLA requirement: lower latency bar
  c.latency_p95_threshold_ms = 200.0

  # Busy system: raise minimum utilization bar
  c.utilization_min_count    = 20

  # Weight operational gaps higher
  c.severity_weights         = { denial: 1.5, failure: 1.3, latency: 1.2 }
end
```

Freeze configuration before analysis to prevent drift:

```ruby
WildGapMiner.configuration.freeze!
```

---

## Step 3: Run Analysis

```ruby
report = WildGapMiner.analyze('/tmp/telemetry.jsonl')
```

For manual pipeline control:

```ruby
parser  = WildGapMiner::Ingestion::ExportParser.new
parsed  = parser.parse_file('/tmp/telemetry.jsonl')
report  = WildGapMiner::Report::Builder.new(
  records: parsed[:records].merge(header: parsed[:header])
).build
```

---

## Step 4: Review the Report

```ruby
summary = report.summary
puts "Total gaps: #{summary[:total_gaps]}"
puts "High severity: #{summary[:high_severity_count]}"
puts "Average severity: #{summary[:severity_avg]}"
puts ""
puts "Top actions by max severity:"
summary[:top_actions].each do |entry|
  puts "  #{entry[:action]}: #{entry[:max_severity].round(2)}"
end
```

Inspect specific gap types:

```ruby
denial_gaps = report.gaps_of_type(:denial)
puts "Denial gaps (#{denial_gaps.length}):"
denial_gaps.each do |gap|
  puts "  [#{gap.severity.round(2)}] #{gap.action}"
  puts "     #{gap.recommendation}"
end
```

---

## Step 5: Export Reports

### JSON (for downstream tooling)

```ruby
WildGapMiner::Export::JsonExporter.new.write(report, '/tmp/gaps.json')
```

### Markdown (for human review)

```ruby
WildGapMiner::Export::MarkdownExporter.new.write(report, '/tmp/gaps.md')
```

---

## Error Handling

```ruby
begin
  report = WildGapMiner.analyze(path)
rescue WildGapMiner::ParseError => e
  warn "Export file is malformed: #{e.message}"
rescue WildGapMiner::SchemaError => e
  warn "Export header is invalid: #{e.message}"
rescue WildGapMiner::ConfigurationError => e
  warn "Configuration error: #{e.message}"
end
```

---

## Recurring Analysis (Cron / Scheduled Job)

For periodic analysis, reset configuration between runs to avoid state bleed:

```ruby
def analyze_export(path)
  WildGapMiner.reset_configuration!
  WildGapMiner.configure { |c| c.denial_threshold = 0.1 }
  WildGapMiner.analyze(path)
end
```

---

## Interpreting Severity Levels

| Severity Range | Label | Action |
|---------------|-------|--------|
| 0.7 – 1.0 | HIGH | Investigate immediately |
| 0.4 – 0.69 | MEDIUM | Schedule for next sprint |
| 0.0 – 0.39 | LOW | Backlog for awareness |

Weights amplify or reduce raw severity. A `denial` gap at 0.5 with weight 1.5 becomes 0.75 (HIGH).
