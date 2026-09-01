/// Per-endpoint capture override. Keyed in [MonitorConfig.endpointRules] by
/// the rule's [pattern].
///
/// Pattern matching is glob-style on the request path:
///   - `*`  matches any sequence within a single path segment
///   - `**` matches any sequence including `/`
/// Example: `/wearables/**` matches `/wearables/health-data` and
/// `/wearables/auth/fitbit/code`.
class EndpointRule {
  const EndpointRule({
    required this.pattern,
    this.enabled = true,
    this.captureRequestHeaders,
    this.captureRequestBody,
    this.captureResponseHeaders,
    this.captureResponseBody,
    this.alertLatencyMs,
  });

  final String pattern;
  final bool enabled;
  final bool? captureRequestHeaders;
  final bool? captureRequestBody;
  final bool? captureResponseHeaders;
  final bool? captureResponseBody;
  final int? alertLatencyMs;

  EndpointRule copyWith({
    String? pattern,
    bool? enabled,
    bool? captureRequestHeaders,
    bool? captureRequestBody,
    bool? captureResponseHeaders,
    bool? captureResponseBody,
    int? alertLatencyMs,
  }) {
    return EndpointRule(
      pattern: pattern ?? this.pattern,
      enabled: enabled ?? this.enabled,
      captureRequestHeaders:
          captureRequestHeaders ?? this.captureRequestHeaders,
      captureRequestBody: captureRequestBody ?? this.captureRequestBody,
      captureResponseHeaders:
          captureResponseHeaders ?? this.captureResponseHeaders,
      captureResponseBody: captureResponseBody ?? this.captureResponseBody,
      alertLatencyMs: alertLatencyMs ?? this.alertLatencyMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'pattern': pattern,
        'enabled': enabled,
        if (captureRequestHeaders != null)
          'captureRequestHeaders': captureRequestHeaders,
        if (captureRequestBody != null)
          'captureRequestBody': captureRequestBody,
        if (captureResponseHeaders != null)
          'captureResponseHeaders': captureResponseHeaders,
        if (captureResponseBody != null)
          'captureResponseBody': captureResponseBody,
        if (alertLatencyMs != null) 'alertLatencyMs': alertLatencyMs,
      };

  factory EndpointRule.fromJson(Map<dynamic, dynamic> json) => EndpointRule(
        pattern: json['pattern'] as String,
        enabled: (json['enabled'] as bool?) ?? true,
        captureRequestHeaders: json['captureRequestHeaders'] as bool?,
        captureRequestBody: json['captureRequestBody'] as bool?,
        captureResponseHeaders: json['captureResponseHeaders'] as bool?,
        captureResponseBody: json['captureResponseBody'] as bool?,
        alertLatencyMs: (json['alertLatencyMs'] as num?)?.toInt(),
      );
}
