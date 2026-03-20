# 005-DR-REFF — Configuration Reference

**Repo:** wild-gap-miner
**Status:** v1

## Overview

Configuration is managed through `WildGapMiner::Configuration`. Use `WildGapMiner.configure` to
set values in a block, or call setters directly on `WildGapMiner.configuration`.

```ruby
WildGapMiner.configure do |c|
  c.denial_threshold = 0.25
  c.severity_weights = { denial: 1.5 }
end
```

Call `WildGapMiner.reset_configuration!` to restore all defaults.

---

## Threshold Settings

### `denial_threshold` (Float)

Default: `0.2`
Range: 0.0 – 1.0

Actions with a denial outcome percentage above this value are flagged as denial gaps.
A value of 0.2 means "flag anything denied more than 20% of the time."

### `failure_threshold` (Float)

Default: `0.15`
Range: 0.0 – 1.0

Actions with a failure rate (1.0 - success_rate) above this value are flagged as failure gaps.

### `latency_p95_threshold_ms` (Float)

Default: `500.0`
Range: >= 0.0

Actions with a p95 latency strictly above this value (in milliseconds) are flagged as latency gaps.
Severity scales from 0.0 at the threshold to 1.0 at 2x the threshold.

### `utilization_min_count` (Integer)

Default: `5`
Range: >= 0

Actions invoked fewer times than this value are flagged as utilization gaps.
Severity is inversely proportional: 0 invocations → severity 1.0; `min_count - 1` invocations → low severity.

### `coverage_min_fraction` (Float)

Default: `0.3`
Range: 0.0 – 1.0

Callers using fewer distinct actions than this fraction of all available actions are flagged as
coverage gaps. 0.3 means "flag callers using less than 30% of all known actions."

### `pattern_min_occurrences` (Integer)

Default: `3`
Range: >= 1

Behavioral patterns (sequences) must appear at least this many times to be flagged.

---

## Other Settings

### `max_gaps_per_type` (Integer)

Default: `50`
Range: >= 1

Each analyzer returns at most this many gaps, sorted by severity descending. Prevents reports from
being overwhelmed by a single gap type when many actions exceed a threshold.

### `severity_weights` (Hash)

Default: all gap types weighted `1.0`

```ruby
c.severity_weights = {
  denial:      1.0,
  failure:     1.0,
  latency:     1.0,
  utilization: 1.0,
  coverage:    1.0,
  pattern:     1.0
}
```

Values > 1.0 amplify severity for that gap type. Values < 1.0 reduce it. Values are merged with
the defaults, so you only need to specify the types you want to change. After weight application,
severity is clamped to [0.0, 1.0].

---

## Immutable Configuration

Call `config.freeze!` after configuration to prevent further modifications:

```ruby
WildGapMiner.configure { |c| c.denial_threshold = 0.3 }
WildGapMiner.configuration.freeze!

WildGapMiner.configuration.denial_threshold = 0.5  # raises FrozenError
```

This is useful in production to prevent accidental configuration drift.

---

## Validation Errors

All setters validate their inputs and raise `WildGapMiner::ConfigurationError` on invalid values:

- Float settings reject non-numeric values and out-of-range values
- Integer settings reject non-Integer values and out-of-range values
- `severity_weights` rejects non-Hash values
