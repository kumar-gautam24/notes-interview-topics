import 'dart:async';

import 'package:dio/dio.dart';

import '../interceptor/api_monitor_interceptor.dart';
import '../matching/endpoint_matcher.dart';
import '../storage/api_log_store.dart';
import '../storage/exporter.dart';
import 'config_store.dart';
import 'monitor_config.dart';

/// Public facade for the API monitoring feature. Consumers interact with this
/// singleton only — internal layers (store, config, redaction, matcher) are
/// implementation details.
///
/// Lifecycle:
///   1. `await ApiMonitor.instance.init()`        // sets up Hive boxes
///   2. `dio.interceptors.add(ApiMonitor.instance.interceptor)`
///   3. UI: push `ApiMonitorHomeScreen()`
///
/// All methods are safe to call after `init()`. Calling them before is a
/// no-op (records will simply be dropped). The whole feature is intended to
/// be guarded by `kDebugMode` at the call site.
class ApiMonitor {
  ApiMonitor._();

  static final ApiMonitor instance = ApiMonitor._();

  final ApiLogStore _store = ApiLogStore();
  final ConfigStore _configStore = ConfigStore();
  late final ApiMonitorInterceptor _interceptor;
  Future<void>? _initFuture;

  Dio? _hostDio;
  String? Function()? _screenProvider;

  ApiLogStore get store => _store;
  ConfigStore get configStore => _configStore;
  Interceptor get interceptor => _interceptor;
  Exporter get exporter => const Exporter();

  /// Optional: register the host's primary [Dio] instance so the detail
  /// screen can offer "Replay request". Without this, replay is hidden.
  void attachDio(Dio dio) {
    _hostDio = dio;
  }

  Dio? get hostDio => _hostDio;

  /// Optional: register a callback that returns the active screen name.
  /// Wire this to your `RouteObserver` (the host already has
  /// `analytics_route_observer.dart`) so each captured call gets a
  /// `screenName` for correlation.
  void setCurrentScreenProvider(String? Function() provider) {
    _screenProvider = provider;
  }

  String? currentScreen() {
    try {
      return _screenProvider?.call();
    } catch (_) {
      return null;
    }
  }

  /// Idempotent and safe to call concurrently — the second caller
  /// awaits the same in-flight init future rather than re-running.
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    await _configStore.init();
    final cfg = _configStore.current;
    await _store.init(
      maxRecords: cfg.retention.maxRecords,
      ttlDays: cfg.retention.ttlDays,
    );
    _interceptor = ApiMonitorInterceptor(
      store: _store,
      configProvider: () => _configStore.current,
      matcher: const EndpointMatcher(),
      screenProvider: currentScreen,
    );
    // Apply retention changes live whenever config is saved.
    _configStore.changes.listen((cfg) {
      _store.updateRetention(
        maxRecords: cfg.retention.maxRecords,
        ttlDays: cfg.retention.ttlDays,
      );
    });
  }

  bool get isInitialized => _initFuture != null;

  Future<void> updateConfig(MonitorConfig config) =>
      _configStore.save(config);

  Future<void> clearLogs() => _store.clear();
}
