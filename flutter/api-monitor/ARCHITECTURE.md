# API Monitor — Architecture, Gaps, and Future Scope

A strict-principles review of the current implementation. Written for a
future maintainer who wants to know not just **what's there**, but
**what's missing**, **why** the trade-offs were made, and **where to go
next**.

---

## 1. Architectural overview

### Layered structure

```
            ┌──────────────────────────────────────┐
            │  ui/    (screens, widgets, palette)  │
            └──────────────┬───────────────────────┘
                           │ reads via streams
            ┌──────────────▼───────────────────────┐
            │  core/   facade   config   store     │
            └─────┬───────────┬──────────┬─────────┘
                  │           │          │
          ┌───────▼───┐ ┌─────▼────┐ ┌───▼────────────┐
          │ matching/ │ │redaction/│ │ storage/       │
          │ glob+tmpl │ │ pii      │ │ ring + percentile│
          └───────────┘ └──────────┘ └────────────────┘
                  ▲           ▲          ▲
                  └─────┬─────┴──────────┘
                        │
            ┌───────────▼──────────────┐
            │ interceptor/             │
            │  Dio Interceptor (entry) │
            └──────────────────────────┘
```

### Principles applied

| Principle | How |
|---|---|
| Single Responsibility | Each file does one thing: matcher matches, redactor redacts, store stores, aggregator aggregates |
| Dependency direction | UI depends on core; core depends on storage / matching / redaction; **never the reverse** |
| Open/Closed | Behavior changes via config (rules, redaction lists) without code edits |
| Fail-safe | Every interceptor path has `try/catch`; a monitor bug never breaks an API call |
| No host coupling | The package has zero `package:<AppName>_AI/...` imports inside `src/`, so it can be lifted out as-is |
| Read-only side-effects on requests | Interceptor never mutates request/response objects beyond writing to `options.extra` for correlation |
| Testability | Pure functions in `matching/`, `redaction/`, `storage/aggregator.dart`; no globals required for unit tests |

### Principles intentionally not applied yet

| Principle | Why deferred |
|---|---|
| Plug-in storage backend | Single Hive backend is enough for v1; abstracting now would be speculative |
| Plug-in transport (WebSocket source) | v1 scope is REST-only; no value in an interface with one implementation |
| DI container | The package has one singleton; introducing GetIt/Riverpod just to inject a stub clock is overkill |

---

## 2. Strict-principles audit — gaps and weaknesses

### A. Capture correctness

**A1. Total-only timing.**
The interceptor records `request_start → response_complete` but does not
break out DNS / TCP / TLS / TTFB / content-download. The plan called for
a waterfall; what landed is one bar.
- **Why**: per-stage breakdown requires wrapping `HttpClientAdapter` and
  pulling timing off `HttpClient` events; this raised the integration
  risk above what v1 budgeted for.
- **Cost**: timing waterfall has only one stage. P95 still works.
- **Fix path**: wrap `IOHttpClientAdapter` once, write timestamps into
  `RequestOptions.extra`, read in `onResponse`. ~80 LOC.

**A2. Network type field is dead.**
`networkType` was specified in the plan, omitted in the model. Adding
`connectivity_plus` would cover it.
- **Cost**: cannot explain "why was that call slow?" with "user was on
  3G".

**A3. Response body for streamed responses.**
Dio's `BackgroundTransformer` is used in this app. For very large
streamed responses, the body Dio hands us at `onResponse` is the fully
decoded payload — we don't see chunked deltas. Acceptable for REST,
but **not** suitable if anyone enables streaming Dio responses later.

**A4. FormData handling is shallow.**
For multipart uploads we render `[FormData] key=value …` instead of the
real binary payload. Files are recorded as `<file:filename>`. Adequate
for debugging, but loses size accuracy for the request body
(`requestBodySize` reflects the rendered string, not the wire bytes).

### B. Storage and persistence

**B1. Two Hive boxes, no transactional guarantee.**
`ApiLogStore` keeps records in `api_monitor_logs` and insertion order in
`api_monitor_logs_idx`. If the process is killed between the two
`put`/`delete` calls, the boxes can drift. The damage is limited — the
purge logic is tolerant of orphans, and dev-tool data is non-critical —
but it's not strictly correct.
- **Fix path**: write `{record, ts}` into a single value and skip the
  index box. Trade-off: `_enforceCap()` becomes O(N) instead of O(1).

**B2. JSON-string serialization is wasteful.**
We `jsonEncode` on write and `jsonDecode` on read. For 1,000 records
with full bodies that's measurable. Hive supports binary `TypeAdapter`
classes — we skipped them only because `build_runner` is broken on the
current branch.
- **Fix path**: hand-write a `TypeAdapter` for `ApiCallRecord` (no
  codegen needed). ~100 LOC, ~5–10× faster reads.

**B3. No background-isolate work.**
Serialization happens on the main isolate. For small bodies it's
negligible; for a 16 KB body × every call × main thread that's a few ms
each. Not visible today but a regression hazard.
- **Fix path**: `compute()` for serialization, or move to an
  `Isolate`-hosted `IsolatedHiveStore`.

**B4. Body cap is byte-counted but stored as a UTF-8 string.**
`Redactor.cap()` slices on byte boundary then decodes with
`allowMalformed: true`. Correct but cosmetic — a multibyte char can
render as `?` at the boundary. Fine for debugging.

### C. Configuration

**C1. No env/.env layering.**
The config has one source: the Hive box. There's no way to set defaults
per environment (dev vs staging) without editing code. For a debug-only
tool that's tolerable, but a richer team workflow would want it.
- **Fix path**: `MonitorConfig.fromEnv(dotenv)` overlay, applied if no
  saved config exists.

**C2. No remote config.**
A QA engineer cannot turn on body capture for a specific user without
shipping a build. We deliberately scoped this out; calling it out as a
gap.

**C3. Endpoint rules are not ordered.**
`endpointRules` is a `Map<String, EndpointRule>` keyed by pattern.
"First match wins" — but in a `Map` the iteration order is insertion
order, not priority. A user editing rules cannot move "more specific
rule above less specific rule".
- **Fix path**: change to `List<EndpointRule>` with explicit ordering;
  the UI gains drag-to-reorder.

**C4. No per-rule body cap.**
The body cap is global. A user who wants 4 KB caps for `/chat/**` but
64 KB for `/wearables/**` cannot express that.

### D. Redaction

**D1. JSON-only body redaction.**
If the body is form-encoded (`a=1&b=2`), XML, or a custom format, the
redactor leaves it alone — it tries `jsonDecode`, fails, returns the
input. So a `password=secret` in form-encoded bodies is **not** redacted.
- **Fix path**: add a form-urlencoded redactor; gated by content-type.

**D2. URL path is never redacted.**
`/users/+91XXXXXXXXXX/profile` would log the phone number in the path.
Redaction only operates on query params. A field like
`urlPathSegmentDenylist` or pattern-based path masking is missing.

**D3. Header-value matching is exact (key-based only).**
We mask values for denylisted keys, but we don't scan **values** of
non-denylisted headers for things that look like JWTs or credit cards.
For a careful denylist this is fine; for an unknown header carrying a
secret, it leaks.

**D4. The `authTokenRaw` field is persisted to Hive.**
By design — the user wanted easy copy. But the dev tool's database now
contains plaintext bearer tokens that survive app restart and last 7
days by default. The Hive box is **not** encrypted (the app's other
Hive box is). On a developer's device this is acceptable; on a stolen
device less so.
- **Fix path**: encrypt the monitor's logs box with the same secure key
  used by `HiveCacheService`. Or add a config toggle to omit
  `authTokenRaw` entirely.

### E. Aggregation

**E1. Percentile is "nearest rank", not interpolated.**
`(p * (n-1)).round()` is a quick approximation. For small N (< 20) it
overstates P95 by one bucket. Acceptable for a debug tool.

**E2. Aggregates are not bucketed by time.**
"P95 over the last hour" would require windowing. Today, the aggregator
sees whatever happens to be in the ring. If you ran a load test 30
minutes ago and now make 5 normal calls, your P95 is dominated by old
data.
- **Fix path**: optional time-window filter on `aggregate()`.

**E3. No drift detection.**
The plan's "spike detection" anti-goal still holds. But even basic
"P95 is 2× the rolling P50" highlighting would be cheap and useful.

### F. UI

**F1. Timeline is not virtualized for filter changes.**
The filter pipeline rebuilds the list on every keystroke. `ListView.builder`
handles it but at 1,000 records with body search every keystroke walks
all bodies. Today fine; not future-proof.
- **Fix path**: debounce the search input; index searchable text.

**F2. No accessibility audit.**
Custom dark theme means we ignored Material's high-contrast tokens.
Screen readers should still work (semantics inherited from
Text/Switch/etc.), but font sizes are hard-coded.

**F3. Cannot pause capture without disabling it.**
"Stop capturing for 30s while I reproduce" requires toggling Master OFF
then ON. A "pause" with a timer would be friendlier.

**F4. No way to pin a record.**
With a 1,000-cap ring buffer, a record you care about can be pushed out
by noisy traffic. A "pin" flag that exempts a record from eviction is
missing.

### G. Error handling and resilience

**G1. Init failures are swallowed.**
In `main_common.dart` we `try/catch` around `ApiMonitor.instance.init()`
and only `debugPrint`. If Hive corruption breaks the box, the dev tool
will silently behave like it's disabled. A surfaced toast or a
fallback "in-memory only" mode would be better.

**G2. Hive `openBox` race on hot restart.**
If `init()` is called twice in quick succession (hot restart in IDE),
the singleton's `_initialized` guard prevents the second open, but
`Hive.openBox` for already-open boxes is fine. The race window is
small but technically present.

**G3. Stream from store has no backpressure.**
Each `upsert` calls `controller.add(null)`. With 100 calls/sec the
stream emits 100/sec; UI rebuilds 100/sec. Acceptable today; a
`debounce(50ms)` on the stream would be cheap insurance.

### H. Testing

**H1. No tests yet.**
The plan listed unit tests for matcher, redactor, store, aggregator.
Pure functions, easy to test. **None landed.** This is the largest
single gap.
- **Fix path**: 4 test files, each ~50 LOC. Should be next merge.

### I. Deployment / lifecycle

**I1. No way to ship a snapshot to engineering.**
Today a user can copy JSON to clipboard, but on a real device that's
already a friction step. A "share file" / "email" / "drop on Slack"
target is missing — addressed in the **Export** section below.

**I2. No build-time gating beyond `kDebugMode`.**
Release builds drop the package via tree-shaking, but profile builds
still include it (kDebugMode is false there). Usually fine, but if
you're profiling a release-like build with monitoring code attached
that's a confusing surprise.

---

## 3. Future scope, prioritized

### Tier 1 — Should land soon

| # | Item | Estimated cost | Justification |
|---|---|---|---|
| 1 | **Unit tests** for matcher, redactor, ring store, aggregator | 1 day | Catches regressions; makes refactors safe |
| 2 | **Per-stage timing** (DNS / connect / TLS / TTFB / download) | 1 day | The headline UX feature was promised in the plan |
| 3 | **Export single record + export all** as JSON file via share-sheet | ½ day | Asked for; addresses I1 |
| 4 | **Encrypt the logs box** (or add toggle to omit `authTokenRaw`) | ½ day | Closes D4 |
| 5 | **Form-urlencoded body redaction** | ½ day | Closes D1; non-trivial leak risk |

### Tier 2 — Quality of life

| # | Item |
|---|---|
| 6 | Pin a record to exempt from eviction (F4) |
| 7 | Pause-with-timer capture button (F3) |
| 8 | URL path segment redaction (D2) |
| 9 | Endpoint rule ordering as a List with drag-to-reorder (C3) |
| 10 | Per-rule body cap (C4) |
| 11 | Search-input debounce + searchable-text index (F1) |
| 12 | Hand-written Hive `TypeAdapter` for `ApiCallRecord` (B2) |
| 13 | Single-box transactional storage (B1) |
| 14 | Time-windowed aggregates (E2) |
| 15 | Drift highlighting in Endpoints tab (E3) |

### Tier 3 — New surfaces

| # | Item |
|---|---|
| 16 | **WebSocket source adapter** for `ChatWebSocketService` and Sarvam STT |
| 17 | **Remote sink** plugin (Datadog / Sentry / custom) |
| 18 | **Replay request** — re-fire a captured request from the detail screen |
| 19 | **Compare two records** — side-by-side diff for the same endpoint |
| 20 | **Network type** capture via `connectivity_plus` (A2) |
| 21 | **Off-isolate serialization** via `compute()` (B3) |
| 22 | **Crash bundle** — last 50 calls auto-attached to Crashlytics reports |
| 23 | **Trace ID** propagation header (`X-Trace-ID`) for backend correlation |
| 24 | **Search-by-body-hash** to find duplicate requests |

### Tier 4 — Speculative / explicit non-goals today

| # | Item | Why not now |
|---|---|---|
| 25 | Anomaly detection / alerting | Pull-only inspector by design; alerts cross into observability product territory |
| 26 | Multi-user / cross-session aggregation history | Requires backend |
| 27 | A B-test of redaction rules per build flavor | Niche |
| 28 | Mock-server replay (replay captured response when offline) | Different feature; would deserve its own package |

---

## 4. What "very good" looks like, in one paragraph

A future maintainer dropping in this package on day 1 should be able to
add **one line** to their Dio setup, see every request in a
mobile-friendly inspector, and feel confident that nothing sensitive
is logged unless they explicitly opted in. They should be able to
narrow to one slow endpoint in 5 seconds, copy the cURL, paste it into
Postman, and reproduce server-side. They should never wonder whether
the monitor is making the app slower, and they should never see the
monitor crash. **The current implementation gets ~80% of the way
there.** The remaining 20% is the Tier 1 list above.
