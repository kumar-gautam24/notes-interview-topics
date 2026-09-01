import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/monitor_config.dart';
import '../matching/endpoint_matcher.dart';
import '../model/api_call_record.dart';
import '../model/enums.dart';
import '../model/timing_breakdown.dart';
import '../redaction/redactor.dart';
import '../storage/api_log_store.dart';

/// Read-only Dio interceptor that captures every request and writes a single
/// [ApiCallRecord] per call. Never mutates request/response — a bug here must
/// never break a real API call, so every capture path is wrapped in try/catch.
class ApiMonitorInterceptor extends Interceptor {
  ApiMonitorInterceptor({
    required ApiLogStore store,
    required this.configProvider,
    EndpointMatcher matcher = const EndpointMatcher(),
    String? Function()? screenProvider,
  })  : _store = store,
        _matcher = matcher,
        _screenProvider = screenProvider;

  final ApiLogStore _store;
  final MonitorConfig Function() configProvider;
  final EndpointMatcher _matcher;
  final String? Function()? _screenProvider;

  static const _idKey = '__apiMonitorId';
  static const _startKey = '__apiMonitorStart';
  static const _tagKey = 'monitor.tag';

  static int _counter = 0;
  static String _newId() {
    _counter = (_counter + 1) & 0x7fffffff;
    return '${DateTime.now().microsecondsSinceEpoch}-$_counter';
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    try {
      final config = configProvider();
      if (!config.capturing) {
        handler.next(options);
        return;
      }
      final rule = _matcher.findRule(options.path, config);
      if (rule != null && !rule.enabled) {
        handler.next(options);
        return;
      }

      final id = _newId();
      final now = DateTime.now();
      options.extra[_idKey] = id;
      options.extra[_startKey] = now;

      // Retry detection. Two signals:
      //   1) Dio's same RequestOptions is reused (same `_idKey` already
      //      present) — handled by id collision and rare in practice.
      //   2) The host opted into UploadRetryInterceptor and the previous
      //      attempt's record is the most recent matching method+path
      //      that completed with an error within the last 30 s.
      final retryInfo = _detectRetry(options);

      final captureReqHeaders =
          rule?.captureRequestHeaders ?? config.capture.requestHeaders;
      final captureReqBody =
          rule?.captureRequestBody ?? config.capture.requestBody;

      final redactor = Redactor(config.redaction);
      final rawHeaders = _stringifyHeaders(options.headers);
      final headers =
          captureReqHeaders ? redactor.redactHeaders(rawHeaders) : null;
      final authToken = _extractAuthToken(rawHeaders);
      final bodyText = captureReqBody ? _bodyAsString(options.data) : null;
      final redactedBody =
          bodyText != null ? redactor.redactBody(bodyText) : null;
      final cappedBody =
          Redactor.cap(redactedBody, config.retention.maxBodyBytes);

      final url = redactor.redactUrl(options.uri.toString());

      final record = ApiCallRecord(
        id: id,
        startedAt: now,
        completedAt: null,
        method: options.method.toUpperCase(),
        url: url,
        endpointTemplate: _matcher.templateFor(options.path),
        requestHeaders: headers,
        requestBody: cappedBody,
        requestBodySize: bodyText == null ? 0 : utf8.encode(bodyText).length,
        responseStatus: null,
        responseHeaders: null,
        responseBody: null,
        responseBodySize: 0,
        timing: null,
        cancelled: false,
        errorKind: null,
        errorMessage: null,
        retryCount: retryInfo.count,
        tag: options.extra[_tagKey] as String?,
        requestIdHeader: null,
        authTokenRaw: authToken,
        screenName: _resolveScreen(),
        previousAttemptId: retryInfo.previousId,
      );
      _store.upsert(record);
    } catch (_) {
      // Never fail a real request because of a monitor bug.
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    try {
      _finalize(response: response, error: null);
    } catch (_) {}
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    try {
      _finalize(response: err.response, error: err);
    } catch (_) {}
    handler.next(err);
  }

  void _finalize({
    Response<dynamic>? response,
    DioException? error,
  }) {
    final options = response?.requestOptions ?? error?.requestOptions;
    if (options == null) return;
    final id = options.extra[_idKey] as String?;
    final start = options.extra[_startKey] as DateTime?;
    if (id == null || start == null) return;
    final existing = _store.get(id);
    if (existing == null) return;

    final config = configProvider();
    final rule = _matcher.findRule(options.path, config);
    final captureResHeaders =
        rule?.captureResponseHeaders ?? config.capture.responseHeaders;
    final captureResBody =
        rule?.captureResponseBody ?? config.capture.responseBody;

    final now = DateTime.now();
    final totalMs = now.difference(start).inMilliseconds;

    final redactor = Redactor(config.redaction);
    Map<String, String>? headers;
    if (captureResHeaders && response != null) {
      headers = redactor.redactHeaders(_responseHeaders(response));
    }

    String? bodyText;
    int bodySize = 0;
    if (response != null) {
      bodyText = _bodyAsString(response.data);
      if (bodyText != null) bodySize = utf8.encode(bodyText).length;
    }
    final redactedBody = captureResBody && bodyText != null
        ? redactor.redactBody(bodyText)
        : null;
    final cappedBody =
        Redactor.cap(redactedBody, config.retention.maxBodyBytes);

    ErrorKind? errorKind;
    bool cancelled = false;
    String? errorMessage;
    if (error != null) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          errorKind = ErrorKind.timeout;
          break;
        case DioExceptionType.cancel:
          errorKind = ErrorKind.cancelled;
          cancelled = true;
          break;
        case DioExceptionType.connectionError:
          errorKind = ErrorKind.network;
          break;
        case DioExceptionType.badCertificate:
          errorKind = ErrorKind.network;
          break;
        case DioExceptionType.badResponse:
          errorKind = ErrorKind.badResponse;
          break;
        case DioExceptionType.unknown:
          errorKind = ErrorKind.unknown;
          break;
      }
      errorMessage = error.message ?? error.error?.toString();
    }

    final reqIdHeader = response?.headers.value('x-request-id') ??
        response?.headers.value('X-Request-Id');

    final updated = existing.copyWith(
      completedAt: now,
      responseStatus: response?.statusCode,
      responseHeaders: headers,
      responseBody: cappedBody,
      responseBodySize: bodySize,
      timing: TimingBreakdown(totalMs: totalMs),
      cancelled: cancelled,
      errorKind: errorKind,
      errorMessage: errorMessage,
      requestIdHeader: reqIdHeader,
    );
    _store.upsert(updated);
  }

  // ───────── helpers ─────────

  static const _retryWindow = Duration(seconds: 30);

  ({int count, String? previousId}) _detectRetry(RequestOptions options) {
    // Look for the most recent record matching method+path that
    // completed with an error within [_retryWindow]. If found, this
    // call is treated as its retry.
    final now = DateTime.now();
    String method = options.method.toUpperCase();
    String path = options.path;
    final recent = _store.all();
    for (final prev in recent) {
      if (prev.method != method) continue;
      try {
        if (Uri.parse(prev.url).path != Uri.parse(path).path) continue;
      } catch (_) {
        continue;
      }
      if (prev.completedAt == null) continue;
      if (now.difference(prev.completedAt!) > _retryWindow) break;
      if (!prev.isError) continue;
      return (count: prev.retryCount + 1, previousId: prev.id);
    }
    final hint = (options.extra['retryCount'] as int?) ?? 0;
    return (count: hint, previousId: null);
  }

  String? _resolveScreen() {
    try {
      return _screenProvider?.call();
    } catch (_) {
      return null;
    }
  }

  String? _extractAuthToken(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'authorization') {
        final v = entry.value.trim();
        if (v.isEmpty) return null;
        return v;
      }
    }
    return null;
  }

  Map<String, String> _stringifyHeaders(Map<String, dynamic> raw) {
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (v is List) {
        out[k] = v.join(', ');
      } else {
        out[k] = v?.toString() ?? '';
      }
    });
    return out;
  }

  Map<String, String> _responseHeaders(Response<dynamic> r) {
    final out = <String, String>{};
    r.headers.forEach((name, values) {
      out[name] = values.join(', ');
    });
    return out;
  }

  String? _bodyAsString(dynamic data) {
    if (data == null) return null;
    if (data is String) return data;
    if (data is FormData) {
      final fields = data.fields.map((e) => '${e.key}=${e.value}').join('&');
      final files =
          data.files.map((e) => '${e.key}=<file:${e.value.filename}>').join('&');
      return '[FormData] $fields ${files.isEmpty ? '' : '| $files'}';
    }
    if (data is List<int>) return '[binary ${data.length} bytes]';
    try {
      return jsonEncode(data);
    } catch (_) {
      return data.toString();
    }
  }
}
