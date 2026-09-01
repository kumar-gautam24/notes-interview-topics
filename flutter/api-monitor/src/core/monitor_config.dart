import '../model/endpoint_rule.dart';

class CaptureFlags {
  const CaptureFlags({
    this.requestHeaders = true,
    this.requestBody = true,
    this.responseHeaders = true,
    this.responseBody = true,
    this.timing = true,
  });

  final bool requestHeaders;
  final bool requestBody;
  final bool responseHeaders;
  final bool responseBody;
  final bool timing;

  CaptureFlags copyWith({
    bool? requestHeaders,
    bool? requestBody,
    bool? responseHeaders,
    bool? responseBody,
    bool? timing,
  }) {
    return CaptureFlags(
      requestHeaders: requestHeaders ?? this.requestHeaders,
      requestBody: requestBody ?? this.requestBody,
      responseHeaders: responseHeaders ?? this.responseHeaders,
      responseBody: responseBody ?? this.responseBody,
      timing: timing ?? this.timing,
    );
  }

  Map<String, dynamic> toJson() => {
        'requestHeaders': requestHeaders,
        'requestBody': requestBody,
        'responseHeaders': responseHeaders,
        'responseBody': responseBody,
        'timing': timing,
      };

  factory CaptureFlags.fromJson(Map<dynamic, dynamic> json) => CaptureFlags(
        requestHeaders: (json['requestHeaders'] as bool?) ?? true,
        requestBody: (json['requestBody'] as bool?) ?? true,
        responseHeaders: (json['responseHeaders'] as bool?) ?? true,
        responseBody: (json['responseBody'] as bool?) ?? true,
        timing: (json['timing'] as bool?) ?? true,
      );
}

class RetentionConfig {
  const RetentionConfig({
    this.maxRecords = 1000,
    this.maxBodyBytes = 16 * 1024,
    this.ttlDays = 7,
  });

  final int maxRecords;
  final int maxBodyBytes;
  final int ttlDays;

  RetentionConfig copyWith({
    int? maxRecords,
    int? maxBodyBytes,
    int? ttlDays,
  }) {
    return RetentionConfig(
      maxRecords: maxRecords ?? this.maxRecords,
      maxBodyBytes: maxBodyBytes ?? this.maxBodyBytes,
      ttlDays: ttlDays ?? this.ttlDays,
    );
  }

  Map<String, dynamic> toJson() => {
        'maxRecords': maxRecords,
        'maxBodyBytes': maxBodyBytes,
        'ttlDays': ttlDays,
      };

  factory RetentionConfig.fromJson(Map<dynamic, dynamic> json) =>
      RetentionConfig(
        maxRecords: (json['maxRecords'] as num?)?.toInt() ?? 1000,
        maxBodyBytes: (json['maxBodyBytes'] as num?)?.toInt() ?? 16 * 1024,
        ttlDays: (json['ttlDays'] as num?)?.toInt() ?? 7,
      );
}

class RedactionConfig {
  const RedactionConfig({
    this.headerDenylist = const [
      'authorization',
      'cookie',
      'set-cookie',
      'x-api-key',
      'api-subscription-key',
    ],
    this.bodyJsonKeys = const [
      'password',
      'otp',
      'token',
      'access_token',
      'refresh_token',
      'id_token',
      'authorization',
    ],
    this.urlQueryDenylist = const [
      'token',
      'access_token',
      'api_key',
      'apikey',
    ],
  });

  final List<String> headerDenylist;
  final List<String> bodyJsonKeys;
  final List<String> urlQueryDenylist;

  RedactionConfig copyWith({
    List<String>? headerDenylist,
    List<String>? bodyJsonKeys,
    List<String>? urlQueryDenylist,
  }) {
    return RedactionConfig(
      headerDenylist: headerDenylist ?? this.headerDenylist,
      bodyJsonKeys: bodyJsonKeys ?? this.bodyJsonKeys,
      urlQueryDenylist: urlQueryDenylist ?? this.urlQueryDenylist,
    );
  }

  Map<String, dynamic> toJson() => {
        'headerDenylist': headerDenylist,
        'bodyJsonKeys': bodyJsonKeys,
        'urlQueryDenylist': urlQueryDenylist,
      };

  factory RedactionConfig.fromJson(Map<dynamic, dynamic> json) {
    List<String> readList(dynamic raw, List<String> fallback) {
      if (raw is List) return raw.map((e) => e.toString()).toList();
      return fallback;
    }

    const defaults = RedactionConfig();
    return RedactionConfig(
      headerDenylist:
          readList(json['headerDenylist'], defaults.headerDenylist),
      bodyJsonKeys: readList(json['bodyJsonKeys'], defaults.bodyJsonKeys),
      urlQueryDenylist:
          readList(json['urlQueryDenylist'], defaults.urlQueryDenylist),
    );
  }
}

class MonitorConfig {
  const MonitorConfig({
    this.enabled = true,
    this.paused = false,
    this.capture = const CaptureFlags(),
    this.retention = const RetentionConfig(),
    this.redaction = const RedactionConfig(),
    this.endpointRules = const {},
  });

  final bool enabled;

  /// Soft toggle: when true, the interceptor stops capturing new calls
  /// but the existing log and UI remain accessible. Distinct from
  /// [enabled]: pausing preserves intent ("come back later"), disabling
  /// turns the whole feature off.
  final bool paused;

  final CaptureFlags capture;
  final RetentionConfig retention;
  final RedactionConfig redaction;

  /// Keyed by rule pattern. Order is not guaranteed; first matching rule wins
  /// in [findRuleFor].
  final Map<String, EndpointRule> endpointRules;

  bool get capturing => enabled && !paused;

  MonitorConfig copyWith({
    bool? enabled,
    bool? paused,
    CaptureFlags? capture,
    RetentionConfig? retention,
    RedactionConfig? redaction,
    Map<String, EndpointRule>? endpointRules,
  }) {
    return MonitorConfig(
      enabled: enabled ?? this.enabled,
      paused: paused ?? this.paused,
      capture: capture ?? this.capture,
      retention: retention ?? this.retention,
      redaction: redaction ?? this.redaction,
      endpointRules: endpointRules ?? this.endpointRules,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'paused': paused,
        'capture': capture.toJson(),
        'retention': retention.toJson(),
        'redaction': redaction.toJson(),
        'endpointRules':
            endpointRules.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory MonitorConfig.fromJson(Map<dynamic, dynamic> json) {
    final rulesRaw = json['endpointRules'];
    final rules = <String, EndpointRule>{};
    if (rulesRaw is Map) {
      rulesRaw.forEach((k, v) {
        if (v is Map) {
          rules[k.toString()] = EndpointRule.fromJson(v);
        }
      });
    }
    return MonitorConfig(
      enabled: (json['enabled'] as bool?) ?? true,
      paused: (json['paused'] as bool?) ?? false,
      capture: json['capture'] is Map
          ? CaptureFlags.fromJson(json['capture'] as Map)
          : const CaptureFlags(),
      retention: json['retention'] is Map
          ? RetentionConfig.fromJson(json['retention'] as Map)
          : const RetentionConfig(),
      redaction: json['redaction'] is Map
          ? RedactionConfig.fromJson(json['redaction'] as Map)
          : const RedactionConfig(),
      endpointRules: rules,
    );
  }
}
