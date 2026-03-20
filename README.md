# wild-gap-miner

Capability gap analysis from session telemetry exports.

Part of the **wild** ecosystem. See `../CLAUDE.md` for ecosystem-level guidance.

**Links:** [wild ecosystem](https://github.com/jeremylongshore) · [wild-session-telemetry](https://github.com/jeremylongshore/wild-session-telemetry)

---

## What It Does

`wild-gap-miner` ingests JSON Lines telemetry exports from `wild-session-telemetry` and surfaces capability gaps: tools that fail too often, actions that get denied, latency outliers, low-coverage callers, and recurring failure patterns.

It runs 6 analyzers, scores each gap by configurable severity weights, generates actionable recommendations, and exports the full report as JSON or Markdown.

## Installation

Add to your Gemfile:

```ruby
gem 'wild-gap-miner'
```

Or install directly:

```bash
gem install wild-gap-miner
```

## Usage

### Convenience method

```ruby
require 'wild_gap_miner'

report = WildGapMiner.analyze('/path/to/export.jsonl')

puts "#{report.summary[:total_gaps]} gaps found"
puts "High severity: #{report.summary[:high_severity_count]}"

report.gaps.first(5).each do |gap|
  puts "#{gap.type}: #{gap.action} (severity #{gap.severity.round(2)})"
  puts "  -> #{gap.recommendation}"
end
```

### With configuration

```ruby
WildGapMiner.configure do |c|
  c.denial_threshold          = 0.15    # Flag actions denied > 15% of the time
  c.failure_threshold         = 0.10    # Flag actions failing > 10% of the time
  c.latency_p95_threshold_ms  = 300.0   # Flag actions with p95 > 300ms
  c.utilization_min_count     = 10      # Flag actions invoked fewer than 10 times
  c.coverage_min_fraction     = 0.25    # Flag callers using < 25% of available actions
  c.pattern_min_occurrences   = 5       # Flag patterns appearing >= 5 times
  c.max_gaps_per_type         = 25      # Cap gaps per analyzer type
  c.severity_weights          = { denial: 1.5, failure: 1.2 }  # Weight certain types higher
end

report = WildGapMiner.analyze('/path/to/export.jsonl')
```

### Export to file

```ruby
json_path = WildGapMiner::Export::JsonExporter.new.write(report, 'gaps.json')
md_path   = WildGapMiner::Export::MarkdownExporter.new.write(report, 'gaps.md')
```

### Manual pipeline

```ruby
parser  = WildGapMiner::Ingestion::ExportParser.new
parsed  = parser.parse_file('/path/to/export.jsonl')
builder = WildGapMiner::Report::Builder.new(
  records: parsed[:records].merge(header: parsed[:header])
)
report  = builder.build
```

## Analyzers

| Analyzer | Detects | Config Key |
|----------|---------|------------|
| DenialAnalyzer | High denial rate per action | `denial_threshold` |
| FailureAnalyzer | High error rate per action | `failure_threshold` |
| LatencyAnalyzer | High p95 latency per action | `latency_p95_threshold_ms` |
| UtilizationAnalyzer | Under-used actions | `utilization_min_count` |
| CoverageAnalyzer | Callers using too few actions | `coverage_min_fraction` |
| PatternAnalyzer | Recurring failure patterns | `pattern_min_occurrences` |

## Configuration Reference

See `000-docs/005-DR-REFF-configuration-reference.md` for full details.

## Architecture

See `000-docs/004-AT-ADEC-architecture-decisions.md` for design rationale.

## Requirements

- Ruby >= 3.2.0
- No external runtime dependencies (JSON is stdlib)

## Development

```bash
bundle install
bundle exec rspec        # 276 examples, 0 failures
bundle exec rubocop      # 0 offenses
```

## License

Nonstandard — Intent Solutions proprietary. See LICENSE.
