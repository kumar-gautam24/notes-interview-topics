# API Monitor

> ## ⚠️ REMOVAL CHECKLIST — RUN BEFORE FINAL SOC AUDIT / PROJECT COMPLETION
>
> This module is dev/QA only. It is gated by `kDebugMode` at every entry
> point so it does not execute in release builds, but the source is still
> compiled into the binary. Once the project ships and the team no longer
> needs the inspector, **delete the module entirely**:
>
> 1. **Delete the directory** `lib/core/dev_tools/api_monitor/`
> 2. **Remove the import + init block** in `lib/main_common.dart`
>    (search for `// TODO(api-monitor)`)
> 3. **Remove the import + interceptor wiring** in
>    `lib/config/injection_container.dart` (search for
>    `// TODO(api-monitor)`)
> 4. **Remove the drawer entry + import** in
>    `lib/features/presentation/drawer/screens/navigation_drawer.dart`
>    (search for `// TODO(api-monitor)`)
> 5. **Remove the Dev Tools tile + import** in
>    `lib/features/presentation/bottom_sheet_test/bottom_sheet_test_screen.dart`
>    (search for `// TODO(api-monitor)`)
> 6. **Remove the `currentScreen` static** added to
>    `lib/core/navigation/analytics_route_observer.dart` (search for
>    `// TODO(api-monitor)`) and the assignment inside `_logRoute()`
> 7. Run `flutter analyze` — all references should be gone.
> 8. Optional: clear stale Hive boxes on debug devices by uninstalling
>    and reinstalling the app once.
>
> Verification: after step 7, `grep -r "api_monitor" lib/` and
> `grep -r "ApiMonitor" lib/` should return zero matches.

---

A self-contained, dev/QA-only API inspector for Flutter apps using **Dio**.
Captures every request and response, persists them locally with **Hive**,
and surfaces an in-app browser (Timeline / Endpoints / Errors / Settings)
that runs as a normal Flutter screen.

Designed to drop into any Flutter project with three lines of glue. No
codegen, no `build_runner`, no extra pub deps beyond what most apps
already have.

---

## Why use it

The standard "log every request to console" interceptor is fragile:

- Output is ephemeral and impossible to filter once it scrolls past
- No request/response correlation, no aggregates, no retention control
- Bodies are dumped raw, no redaction
- Cannot be toggled granularly (whole logger off, or all-on)

This package is a real inspector — searchable, filterable, persistent,
configurable per endpoint and per signal, with redaction baked in.

---

## Features

- **Per-call capture**: method, full URL, headers, request/response body,
  status, total latency, error kind, retry count, network errors, cancellations
- **Auth token panel**: dedicated section in the detail view with reveal/hide,
  copy-with-Bearer and copy-bare actions
- **Sizes**: request and response body sizes shown on every tile and in detail
- **Timing**: total latency in v1; per-stage (DNS / connect / TLS / TTFB / download)
  reserved as nullable for v2
- **PII redaction**: header denylist, JSON-key denylist for bodies, URL
  query-param denylist; Authorization shows `Bearer ****…ab12` in the headers map
- **Endpoint aggregation**: per-template counts, error rate, P50/P95/P99
- **Per-endpoint rules**: glob patterns (`/wearables/**`) with override toggles
  for capture flags and slow-call thresholds
- **Bounded ring storage**: configurable record cap, body cap, and TTL purge
- **Filter bar**: free-text search, method chips, status buckets,
  time-window chips
- **Swipe-to-delete** individual records; **Clear all** in settings
- **Export**: share single record / filtered records / all records as JSON
  or HAR file via the native share sheet; copy any call as cURL
- **Master kill switch** in the app bar
- **Self-contained dark UI** — does not depend on the host app's theme
- **Read-only interceptor** — every capture path is wrapped in `try/catch`,
  so a monitor bug can never break a real API call

---

## Requirements

The host project must already use:

- `dio` (^5.0)
- `hive` + `hive_flutter` (^2.2)

No other dependencies are introduced.

---

## Installation (in this monorepo)

The package lives at `lib/core/dev_tools/api_monitor/`. There is nothing to
install — just import:

```dart
import 'package:<AppName>_AI/core/dev_tools/api_monitor/api_monitor.dart';
```

---

## Wiring (3 steps)

### 1. Initialize after Hive is ready

```dart
import 'package:flutter/foundation.dart';
import 'package:<AppName>_AI/core/dev_tools/api_monitor/api_monitor.dart';

if (kDebugMode) {
  await ApiMonitor.instance.init();
}
```

`init()` is idempotent and safe to call multiple times. It opens two Hive
boxes (`api_monitor_logs`, `api_monitor_logs_idx`) and a config box
(`api_monitor_config`).

### 2. Add the interceptor to your Dio instance

```dart
if (kDebugMode && ApiMonitor.instance.isInitialized) {
  dio.interceptors.add(ApiMonitor.instance.interceptor);
}
```

Place this **after** the auth interceptor (so refreshed tokens are visible)
but you can put it before or after a logging interceptor — they don't
interfere with each other.

### 3. Push the screen from anywhere (debug build only)

```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const ApiMonitorHomeScreen()),
);
```

In this app, the debug drawer has an **API Monitor** entry just below
"Consult Doctor".

---

## Disabling in release builds

The package is intended to be **fully off in release**. The recommended
pattern is to gate every call to `ApiMonitor.instance` with `kDebugMode`,
as shown above. Tree-shaking will remove unreached code paths from the
release binary.

You can additionally gate it on a runtime flag (e.g. an in-app dev menu
unlock) without changing the API.

---

## Configuration

Open the app, go to **API Monitor → Settings**. Every knob is live —
saved instantly to Hive, applied to subsequent calls without restart.

### Master
- **Monitoring enabled** — global kill switch.

### Capture
- Request headers / body
- Response headers / body
- Timing

### Retention
- Max records (default 1,000)
- Max body bytes (default 16 KB; longer bodies are truncated)
- TTL days (default 7; older records are purged on init)

### Endpoint rules
Add glob patterns to override capture for matching paths:
- `*` matches anything except `/`
- `**` matches anything including `/`
- Each rule can disable capture entirely or override per-signal flags
- Each rule can specify `alertLatencyMs` to flag slow calls in the timeline

Example: `/chat/upload*` with `enabled: false` to skip large uploads.

### Redaction
- **Header denylist**: case-insensitive header names whose values are masked
- **Body JSON keys**: case-insensitive keys whose values are replaced with `***`
- **URL query params**: query param names whose values are masked

Defaults cover `Authorization`, `Cookie`, `password`, `otp`, `token`,
`access_token`, `refresh_token`, `id_token`, `api_key`, `apikey`.

The unredacted Authorization value is captured separately into the
`authTokenRaw` field and shown only in the dedicated **Auth Token** panel
of the detail screen, where it is hidden by default and revealed via an
explicit eye toggle.

---

## Public API

```dart
ApiMonitor.instance              // singleton facade
  .init()                        // open boxes, load config
  .interceptor                   // Dio Interceptor to register
  .updateConfig(MonitorConfig)   // persist a new config
  .clearLogs()                   // wipe all stored records
  .store                         // ApiLogStore (advanced)
  .configStore                   // ConfigStore (advanced)
  .isInitialized                 // bool
```

Streams:
- `ApiMonitor.instance.store.changes` — emits when records are added,
  updated, deleted, or cleared. Use with `StreamBuilder` for live UI.
- `ApiMonitor.instance.configStore.changes` — emits the new
  `MonitorConfig` whenever it is saved.

Per-call tagging:
```dart
dio.get(
  '/foo',
  options: Options(extra: {'monitor.tag': 'feature-X'}),
);
```
The tag appears in the call detail header and is searchable.

---

## File layout

```
api_monitor/
├── README.md
├── ARCHITECTURE.md
├── api_monitor.dart                 # public barrel
└── src/
    ├── core/                        # facade, config, config store
    ├── interceptor/                 # Dio interceptor
    ├── matching/                    # URL → template, glob matcher
    ├── model/                       # data classes (no Hive codegen)
    ├── redaction/                   # header / body / query redaction
    ├── storage/                     # ring store + percentile aggregator
    └── ui/                          # all screens and widgets
        └── widgets/
```

The `src/ui/` tree depends on `core` / `model` / `storage` only. It uses
its own dark palette so dropping the package into another project does
not pull in the host app's theme.

---

## Extracting to a standalone package

Three steps:

1. `git mv lib/core/dev_tools/api_monitor packages/api_monitor/lib`
2. Add `pubspec.yaml` declaring `flutter`, `dio`, `hive`, `hive_flutter`
3. Verify `lib/src/**` has no `package:hostApp/...` imports
   (this package was built with that constraint)

Then any host app:

```yaml
dependencies:
  api_monitor:
    path: ../packages/api_monitor
```

---

## Trade-offs and known limitations

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full analysis. Short list:

- **REST/Dio only** — WebSocket traffic (chat, Sarvam STT, LiveKit) is
  not captured in v1
- **Total latency only** — DNS/TCP/TLS/TTFB sub-stages are reserved
  fields but not populated yet
- **In-memory aggregates** — percentiles are computed on demand from
  the persisted ring; no rollups across sessions
- **No remote sink** — purely local; intentional, to avoid PII exfiltration
  surface
- **Hive raw maps, not adapters** — chosen because `build_runner` is
  broken on the current branch and the package targets reusability
- **Single-Dio assumption** — if your host app has multiple `Dio`
  instances, register the interceptor on each one you want monitored
