# API Monitor — Independent Code Review

A second-pass review of the module, distinct from `ARCHITECTURE.md` (which
was authored alongside the code). Findings here were uncovered by reading
the code with no benefit of the doubt and verifying claims against the
source. Each item cites the file and line.

Severity legend: 🔴 fix soon · 🟠 worth doing · 🟡 nice-to-have.

---

## 1. Real bugs (would misbehave today)

### 🔴 1.1 `Settings → Redaction list` editor loses focus on every keystroke

[settings_tab.dart:271](src/ui/settings_tab.dart#L271)

```dart
Widget _listEditor(...) {
  final controller = TextEditingController();   // 👈 new instance every build
  ...
}
```

`SettingsTab` is wrapped in a `StreamBuilder<MonitorConfig>`. Every time
the user toggles any setting, the whole tab rebuilds — and `_listEditor`
is called three times (header denylist, body keys, URL params), each
time creating a fresh `TextEditingController`. The TextField's controller
swap kills focus and discards the in-progress text on every redraw.

**Test it**: open Settings, start typing in "Header denylist" → toggle
"Request body" capture → typing field is reset. Reproducible.

**Fix**: extract the editor into a `StatefulWidget` so the controller
is owned by `State` and disposed in `dispose()`.

---

### 🔴 1.2 `Endpoints` tab drill-down silently shows no results

[endpoints_tab.dart:99-104](src/ui/endpoints_tab.dart#L99-L104)

```dart
TimelineTab(
  initialFilter: TimelineFilter(
    methods: {aggs[i].method},
    search: aggs[i].endpointTemplate,   // e.g. "/profile/{id}"
  ),
)
```

The drill-down passes `endpointTemplate` (`/profile/{id}`) as the
`search` string. The timeline's filter does
`hay.contains(search)` ([timeline_tab.dart:184](src/ui/timeline_tab.dart#L184))
— and real URLs contain `/profile/123`, never the literal `{id}`. So
tapping a row with N calls navigates to a list with **0** matching
records.

**Fix**: filter by `endpointTemplate` directly (add a field to
`TimelineFilter`) instead of routing through full-URL substring search.

---

### 🟠 1.3 In-flight calls are filtered out of the Errors tab

[timeline_tab.dart:140](src/ui/timeline_tab.dart#L140) +
[api_call_record.dart:67-71](src/model/api_call_record.dart#L67-L71)

`isError` returns true only when `cancelled || errorKind != null ||
status >= 400`. A call that has been issued but not yet completed has
none of those — so it's hidden. The Errors tab uses
`TimelineTab(lockErrorsOnly: true)`, meaning **a long-running, possibly
hanging call won't appear there**, which is exactly the case the user
opens Errors to investigate.

**Fix**: extend `isError` to include `completedAt == null && older than X
seconds`, or add an explicit "stuck" filter chip.

---

### 🟠 1.4 Retries overwrite the previous attempt

[api_monitor_interceptor.dart:36-40](src/interceptor/api_monitor_interceptor.dart#L36-L40) +
[api_log_store.dart:43-52](src/storage/api_log_store.dart#L43-L52)

The interceptor generates a *new* id on every `onRequest`, so a Dio
retry will create a fresh record — good, except `retryCount` is read
from `options.extra['retryCount']` ([interceptor:96](src/interceptor/api_monitor_interceptor.dart#L96))
which the host app doesn't populate. Result: every retry attempt has
`retryCount == 0`, so you cannot tell from the timeline that
`/refresh-token` then `/profile` was a retry chain rather than two
unrelated calls.

**Fix**: have the interceptor detect retry-related dio options or
inspect `RequestOptions.extra` for `UploadRetryInterceptor.optInKey`,
and store correlation id pointing to the previous attempt.

---

### 🟠 1.5 `_enforceCap()` operates on `keyAt(0)` of the index box but writes occur in two boxes asynchronously

[api_log_store.dart:55-65](src/storage/api_log_store.dart#L55-L65)

`upsert` does:
1. `_box.put(record.id, encoded)` — record write
2. `_indexBox.put(record.id, ...)` — index write
3. `_enforceCap()` — possibly evicts `keyAt(0)` and deletes from both boxes

If a second `upsert` runs concurrently and step 1 of writer-B lands
between step 1 and step 3 of writer-A, the eviction in writer-A can
delete writer-B's record-key from `_box` before it's even committed to
the index. Net result: `_box` ends up with an entry that's never in the
index → invisible (still counted toward storage), and at boot time the
purge sweep won't see it (it walks the index).

It's narrow — Hive's per-box mutex serialises within a box — but the
two boxes do not share a transaction.

**Fix**: collapse to one box (store `{record, ts}` together), or add an
`AsyncLock`/serial queue around `upsert`.

---

### 🟠 1.6 `ApiMonitor.init()` is not concurrency-safe

[api_monitor.dart:38-58](src/core/api_monitor.dart#L38-L58)

```dart
Future<void> init() async {
  if (_initialized) return;
  await _configStore.init();          // first await — second caller sees _initialized = false
  ...
  _initialized = true;
}
```

Two awaited callers entering before the first sets `_initialized = true`
will both run the entire init body. `_interceptor = ...` is a
late-final assigned twice — runtime exception.

In practice the host calls it once during boot, so the bug is dormant.
But it's a single-line fix and worth applying:

```dart
Future<void>? _initFuture;
Future<void> init() => _initFuture ??= _doInit();
```

---

### 🟡 1.7 HAR export status semantics

[exporter.dart:127-128](src/storage/exporter.dart#L127-L128)

- `'status': r.responseStatus ?? 0` — `0` is not a valid HTTP status.
  Charles and Postman show "0 " in their UI. HAR spec allows omission;
  prefer that for failed/cancelled requests.
- `_statusText` returns `''` for successful responses. Most viewers
  show the value verbatim — so users see "200 " (trailing space) rather
  than "200 OK". A small reason-phrase map would polish this.

---

### 🟡 1.8 `proxy-authorization` not in default header denylist

[monitor_config.dart:91-96](src/core/monitor_config.dart#L91-L96)

`Authorization`, `Cookie`, `Set-Cookie`, `X-API-Key`,
`api-subscription-key` are masked. `Proxy-Authorization` (RFC 7235) is
not. Easy add.

---

### 🟡 1.9 URL path PII not redactable

The redactor handles query params and JSON keys. But <AppName> endpoints
like `/profile/{id}` could become `/profile/+919876543210` if the host
ever puts a phone number in a path segment. There is no way to mask
path segments today. Not exploited by current endpoints, but the gap
should be acknowledged.

---

## 2. Performance traps

### 🟠 2.1 Every Dio call rebuilds and re-walks the entire log

[timeline_tab.dart:42-43](src/ui/timeline_tab.dart#L42-L43)

```dart
StreamBuilder<void>(
  stream: monitor.store.changes,
  builder: (context, _) {
    final all = monitor.store.all();   // O(N) decode + O(N log N) sort
    final filtered = _apply(all, _filter);  // O(N) walk
    ...
```

Every `upsert` (each `onRequest` and `onResponse`) emits on the stream.
A typical screen load fires 5–10 calls × 2 events each = 10–20 emits
clustered in <1 s. Each emit causes the timeline to:

- Decode every stored record's JSON
- Sort by `startedAt`
- Filter by predicate (touches body strings for full-text search)

At the default 1 000-cap, this is fine in dev but quickly becomes a
frame-drop hazard if someone bumps the cap.

**Fix options:**
- Debounce the rebuild stream (`store.changes.debounceTime(50ms)`)
- Cache `all()` until next change instead of recomputing per build
- For the body-text search, build a side-index of lowercased blobs

The same pattern exists in [endpoints_tab.dart:27-28](src/ui/endpoints_tab.dart#L27-L28)
where the aggregator runs the full pipeline on every emit.

---

### 🟠 2.2 Relative-time labels never refresh

[timeline_tab.dart](src/ui/timeline_tab.dart) and
[endpoints_tab.dart](src/ui/endpoints_tab.dart) display
`formatRelative(t)` ("12s ago"). The string is computed at build time
and the surrounding widgets only rebuild on store changes. After a call
finishes, "1s ago" stays at "1s ago" until another request arrives —
which can be misleading when the user is staring at a slow app.

**Fix**: a low-cost `Ticker`/periodic timer (e.g. 5 s) on the home
screen that bumps a `ValueNotifier`, triggering rebuild of the time
labels.

---

### 🟠 2.3 Main-isolate JSON serialization

`jsonEncode` on every `upsert` and `jsonDecode` on every `all()` runs
on the main isolate. Already noted in `ARCHITECTURE.md` (B3) but worth
re-emphasising — at 16 KB body cap × 10 RPS, the marginal cost in
debug isn't free.

---

## 3. Memory & lifecycle

### 🟠 3.1 Stream controllers never closed

[api_log_store.dart:22](src/storage/api_log_store.dart#L22) /
[config_store.dart:19](src/core/config_store.dart#L19)

Both stores expose a `close()` that closes the broadcast controller
and the boxes. Nothing in `ApiMonitor` calls them — there is no
`dispose()` on the facade. In production this doesn't matter (singleton
lives the lifetime of the app); during hot reload / hot restart in dev,
controllers and boxes pile up.

**Fix**: add `Future<void> dispose()` to `ApiMonitor`, call it from a
`WidgetsBindingObserver` on `AppLifecycleState.detached` if you care.

---

### 🟡 3.2 In-flight `Dismissible` reorder race

If a record arrives mid-swipe and the timeline reorders, the
`Dismissible` keyed by `api-call-{id}` keeps its identity but the
visual position shifts. In testing it usually looks fine, but adversarial
load can stutter. Low risk, low effort to mitigate by stabilising the
list order during animation (insert new records at the top *after* the
animation completes).

---

## 4. UX gaps

### 🟠 4.1 No "in-flight" indicator

A call that's been issued but hasn't returned shows status "IN-FLIGHT"
([call_tile.dart:166](src/ui/widgets/call_tile.dart#L166)) but has no
spinner, no live-elapsed counter, no special background. With a hung
network call this looks identical to a 200ms call that's about to
return. Adding a pulsing dot for `completedAt == null` costs nothing
and helps diagnose hangs.

### 🟠 4.2 No undo on swipe-to-delete

Snackbar only confirms the deletion. One slip and the record is gone.
Standard `SnackBarAction(label: 'Undo')` would restore from a transient
in-memory copy.

### 🟠 4.3 No long-press / context menu on a record

Right now you must expand → tap "Open" → use the AppBar action.
Long-press should expose: Copy URL · Copy as cURL · Share · Pin · Delete.

### 🟠 4.4 Status-code search is impossible

Search box matches URL/body text only. A QA tester wanting "all 401s"
must use the `4xx` chip — but that includes 400/403/404 too. Adding
status-code parsing to the search ("401" → status filter) is a few
lines.

### 🟠 4.5 Settings sliders have no text input

[settings_tab.dart:215-261](src/ui/settings_tab.dart#L215-L261) — sliders
for "Max records", "Max body bytes", "TTL (days)" with no numeric input.
Setting `maxRecords` to 100 from 5000 by drag is annoying. Add a
`TextField` next to each slider (a common pattern in dev tools).

### 🟠 4.6 Pause button promised in plan, not built

`ARCHITECTURE.md` lists "pause-with-timer capture button" as Tier 2,
but real users want it before they want HAR export. A single boolean
toggle on `MonitorConfig` (separate from the master switch, with a
visible badge in the AppBar) costs 30 lines.

### 🟡 4.7 Empty-state text is generic

"No API calls captured yet." / "No calls match the current filter." —
fine, but doesn't help diagnose: is the monitor enabled? is the
interceptor wired? has the rule disabled this endpoint? A 2-line hint
panel ("Tip: master switch is OFF" or "Tip: rule `/wearables/**` is
disabling capture for this URL") would be a force-multiplier.

### 🟡 4.8 Light-theme support absent

The package locks itself to a custom dark palette
([_palette.dart](src/ui/_palette.dart)). For an inspector this is fine
— most dev tools are dark — but a host app on a light-only device or a
demo on a projector will look out of place. Optional: read
`MediaQuery.platformBrightness` and pick.

### 🟡 4.9 No "follow new requests" / scroll-pinning

In a noisy app, the timeline reflows under the user. A "🔝 jump to
newest" floating button would be welcome. Or, conversely, a "lock
scroll position" button so the user can read a record without it
scrolling away.

---

## 5. Quality features missing (compared to peer tools)

These are gaps versus what a mature inspector (Charles, Proxyman, Flipper
network plugin, Alice) offers:

| Feature | Why useful |
|---|---|
| **Replay request** | Tap a captured request → re-fire through Dio. The plan mentioned this; nothing was built. |
| **Mock response** | Capture once, intercept future calls and return the captured body — fastest way to test offline behaviour. |
| **Compare two responses** | Same endpoint, two timestamps, side-by-side JSON diff — diagnoses "it changed" bugs in 10 seconds. |
| **Latency chart per endpoint** | A simple 60-second sparkline tells you "endpoint X spiked at minute 3" at a glance. |
| **Persistent filter presets** | "POST + 5xx + last 30m" should be one tap, not three. |
| **Pin a record** | Stops the ring from evicting an interesting call while you keep reproducing. |
| **cURL → fire** | Paste a cURL from a teammate, hit Run, see response. Removes the round-trip via Postman. |
| **Regex search** | Power users want `^/api/v\d+/users` over substring. |
| **Notification on threshold breach** | If `alertLatencyMs` is set, fire an in-app banner — currently the only feedback is a `⚠️ slow` icon you have to spot. |
| **Screen / route correlation** | The plan listed `screenName`; the model omits it. Without it you can't say "every time I open Care Hub, there are 3 calls" — the tool's most common question. |

---

## 6. Code smells / minor

- [endpoint_matcher.dart:8](src/matching/endpoint_matcher.dart#L8) declares
  `const EndpointMatcher();` but every method is `static` — the instance
  is unused.
- `enums.dart` has `CallStatus.inFlight` but no record ever resolves to
  it (the getter at
  [api_call_record.dart:55-65](src/model/api_call_record.dart#L55-L65)
  doesn't check `completedAt == null`). Either compute `inFlight` or
  remove the enum value.
- [api_log_store.dart:107-111](src/storage/api_log_store.dart#L107-L111):
  silent JSON-decode catch returns `null` with no logging. A corrupt
  record disappears with no diagnostic.
- Mixed placeholders for missing data: `'—'` in [_palette.dart:91](src/ui/_palette.dart#L91)
  vs `'UNKNOWN'` in [call_detail_screen.dart:288](src/ui/call_detail_screen.dart#L288).
- [timing_bar.dart:13](src/ui/widgets/timing_bar.dart#L13) uses Dart 3
  records `(_StageLabel, int?)` whereas the rest of the package uses
  classes. Style drift.
- [settings_tab.dart:399-405](src/ui/settings_tab.dart#L399-L405): the
  "Add rule" dialog doesn't validate the glob — an invalid pattern is
  saved silently and matches nothing at runtime.

---

## Recommended priority for follow-up

If this module is to be promoted from "useful prototype" to "team
infrastructure," I would land the fixes in this order:

1. **🔴 1.1 list-editor focus loss** — visible the moment a user tries to
   add a redaction key.
2. **🔴 1.2 Endpoints drill-down filter** — the feature is broken; users
   will think the tool is broken.
3. **🟠 4.6 Pause button** — most-asked dev-tool feature, smallest patch.
4. **🟠 5 Replay + screen correlation** — biggest quality jump per LOC.
5. **🟠 2.1 debounce stream rebuilds** — defends against future scale.
6. **🟠 1.3 + 1.4 in-flight + retry surfacing** — the two states the
   tool currently hides are exactly the states a debugger cares about.

Everything else is real but tier-2.
