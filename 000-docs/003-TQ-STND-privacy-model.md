# 003-TQ-STND — Privacy Model

**Repo:** wild-gap-miner
**Status:** v1

## Principle

wild-gap-miner is an offline analysis tool. It processes telemetry exports that have already been
collected and privacy-filtered by `wild-session-telemetry`. This library does not collect, transmit,
or store any data on its own.

## Data Handled

Input data comes from JSONL export files produced by wild-session-telemetry. That tool is responsible
for privacy-aware collection. By the time data reaches wild-gap-miner, it should already comply with
the privacy guarantees documented in that repo.

wild-gap-miner processes:
- Caller IDs (typically anonymized or session-scoped identifiers)
- Action names (tool names, not content or arguments)
- Outcome codes (success/denied/error/preview/rate_limited — no content)
- Aggregate statistics (counts, rates, percentile latencies)
- Behavioral patterns (action sequences, no payloads)

## What wild-gap-miner Does Not Process

- User-authored content (file contents, prompts, completions)
- PII of any kind
- Raw argument values passed to tools
- Authentication credentials or tokens

## Output Data

Gap reports contain only:
- Derived analytics (rates, counts, severities)
- Action names and caller IDs from the input export
- Descriptive text generated from thresholds and statistics

Reports do not amplify the privacy surface of the input.

## Operator Responsibility

Operators are responsible for:
1. Ensuring input JSONL exports have been appropriately filtered before passing to this library
2. Securing the output report files (they may contain caller IDs and action patterns)
3. Applying any additional anonymization if reports will be shared externally

## No Network Access

This library makes no network calls. It reads from the filesystem and writes to the filesystem.
No telemetry, analytics, or phoning home occurs.
