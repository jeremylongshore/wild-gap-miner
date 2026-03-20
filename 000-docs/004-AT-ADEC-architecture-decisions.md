# 004-AT-ADEC — Architecture Decisions

**Repo:** wild-gap-miner
**Status:** v1

## AD-001: No External Runtime Dependencies

**Decision:** Use only Ruby stdlib (json, time, tmpdir).

**Rationale:** This is an analytics library that will be embedded in other tools. Minimizing the
dependency surface reduces version conflicts, keeps the install fast, and ensures the library works
anywhere Ruby 3.2+ is available.

**Consequence:** JSON parsing via `JSON.parse`/`JSON.generate`. No ActiveSupport. No external HTTP.

---

## AD-002: ExportParser Returns Structured Hash, Not Objects

**Decision:** `ExportParser#parse_file` returns `{ header: ExportHeader, records: Hash<Symbol, Array> }`.

**Rationale:** Keeping parsing separate from analysis gives callers maximum flexibility. They can
inspect parsed records before running analysis, add custom pre-processing, or pass records to
individual analyzers directly.

**Consequence:** `Report::Builder` receives records with an additional `:header` key merged in.
The builder separates the header before passing typed records to analyzers.

---

## AD-003: Analyzers Are Stateless and Independently Instantiable

**Decision:** Each analyzer is a separate class that receives `config:` at initialization and
`records` at `analyze` call time.

**Rationale:** Stateless analyzers are easy to test in isolation. Config injection allows per-analyzer
overrides in advanced use cases without global mutation.

**Consequence:** `Report::Builder` creates a new analyzer instance per run. No caching or memoization.

---

## AD-004: Gap Is an Immutable Value Object

**Decision:** `Gap#initialize` validates all fields and `Gap` does not expose setters.

**Rationale:** Gaps are data produced by analyzers. Making them immutable prevents accidental mutation
downstream (in scoring, enrichment, or export). Validation at construction time ensures no invalid
gap makes it into a report.

**Consequence:** Scoring and recommendation enrichment produce new `Gap` instances rather than
mutating existing ones. This is slightly less performant but correct.

---

## AD-005: Severity Is a Float in [0.0, 1.0]

**Decision:** All gap severities are normalized to a 0.0–1.0 scale.

**Rationale:** A common scale allows severity weights to be applied uniformly across all gap types
and enables consistent sorting, ranking, and display (HIGH/MEDIUM/LOW thresholds).

**Consequence:** Analyzer-specific raw scores must be mapped to [0.0, 1.0]. The `clamp_severity`
helper in `Analyzers::Base` enforces this.

---

## AD-006: LatencyStats Accepts Both `_ms`-Suffixed and Bare Field Names

**Decision:** `LatencyStats` reads `p95_ms` if present, falls back to `p95`.

**Rationale:** The upstream telemetry contract uses `_ms` suffixes. But bare keys may appear in
manually constructed test data or older schema versions. Supporting both prevents ParseErrors on
otherwise valid data.

---

## AD-007: Recommendations Are Advisory, Not Prescriptive

**Decision:** Recommendations are plain strings generated from templates. They are not structured
objects with machine-readable action codes.

**Rationale:** At this stage, gap analysis surfaces issues for human review. Prescriptive machine
actions (e.g., "call this API to fix it") would require integration with other wild repos that do
not exist yet.

**Consequence:** Recommendations can be read in Markdown reports or extracted from JSON exports.
Future work could add structured recommendation codes.

---

## AD-008: TelemetryFixtures Is a Module, Not a Shared Context

**Decision:** `TelemetryFixtures` is a module included via `spec_helper`, not an RSpec shared context.

**Rationale:** Module inclusion means all specs get all builder helpers without any explicit
`include_context` calls. This keeps specs concise and consistent.

**Consequence:** All spec files have access to `build_gap`, `build_event`, etc. by default.
