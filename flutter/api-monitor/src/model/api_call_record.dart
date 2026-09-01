import 'enums.dart';
import 'timing_breakdown.dart';

/// A single captured HTTP call. Stored as a raw map in Hive so we never need
/// `hive_generator` codegen.
class ApiCallRecord {
  const ApiCallRecord({
    required this.id,
    required this.startedAt,
    required this.completedAt,
    required this.method,
    required this.url,
    required this.endpointTemplate,
    required this.requestHeaders,
    required this.requestBody,
    required this.requestBodySize,
    required this.responseStatus,
    required this.responseHeaders,
    required this.responseBody,
    required this.responseBodySize,
    required this.timing,
    required this.cancelled,
    required this.errorKind,
    required this.errorMessage,
    required this.retryCount,
    required this.tag,
    required this.requestIdHeader,
    required this.authTokenRaw,
    required this.screenName,
    required this.previousAttemptId,
  });

  final String id;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String method;
  final String url;
  final String endpointTemplate;

  final Map<String, String>? requestHeaders;
  final String? requestBody;
  final int requestBodySize;

  final int? responseStatus;
  final Map<String, String>? responseHeaders;
  final String? responseBody;
  final int responseBodySize;

  final TimingBreakdown? timing;

  final bool cancelled;
  final ErrorKind? errorKind;
  final String? errorMessage;

  final int retryCount;
  final String? tag;
  final String? requestIdHeader;

  /// Unredacted Authorization header value, captured separately for the
  /// dev-tool's "Auth Token" panel (copy button). Independent of the
  /// `requestHeaders` map, which always contains the redacted version.
  final String? authTokenRaw;

  /// Best-effort name of the active screen at the time of the request,
  /// resolved by the host via [ApiMonitor.setCurrentScreenProvider]. Null
  /// when no provider is registered or no route is active.
  final String? screenName;

  /// When this call is a retry, the id of the immediately preceding
  /// attempt. Lets the detail screen offer a "retry of …" link.
  final String? previousAttemptId;

  /// A call is considered "stuck" when it has been in-flight (no
  /// `completedAt`) longer than this threshold. Stuck calls bubble up
  /// into the Errors tab even though they have no errorKind yet — that
  /// is exactly the state a developer is debugging when they open it.
  static const Duration stuckThreshold = Duration(seconds: 10);

  bool get isInFlight => completedAt == null;

  bool get isStuck =>
      isInFlight && DateTime.now().difference(startedAt) >= stuckThreshold;

  CallStatus get status {
    if (cancelled) return CallStatus.cancelled;
    if (isInFlight) return CallStatus.inFlight;
    if (errorKind == ErrorKind.timeout) return CallStatus.timeout;
    if (errorKind == ErrorKind.network) return CallStatus.networkError;
    if (errorKind != null && responseStatus == null) return CallStatus.unknown;
    return CallStatus.fromStatusCode(responseStatus);
  }

  bool get isError =>
      cancelled ||
      errorKind != null ||
      (responseStatus != null && responseStatus! >= 400) ||
      isStuck;

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'method': method,
        'url': url,
        'endpointTemplate': endpointTemplate,
        'requestHeaders': requestHeaders,
        'requestBody': requestBody,
        'requestBodySize': requestBodySize,
        'responseStatus': responseStatus,
        'responseHeaders': responseHeaders,
        'responseBody': responseBody,
        'responseBodySize': responseBodySize,
        'timing': timing?.toJson(),
        'cancelled': cancelled,
        'errorKind': errorKind?.name,
        'errorMessage': errorMessage,
        'retryCount': retryCount,
        'tag': tag,
        'requestIdHeader': requestIdHeader,
        'authTokenRaw': authTokenRaw,
        'screenName': screenName,
        'previousAttemptId': previousAttemptId,
      };

  factory ApiCallRecord.fromJson(Map<dynamic, dynamic> json) {
    Map<String, String>? readHeaders(dynamic raw) {
      if (raw == null) return null;
      if (raw is Map) {
        return raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
      }
      return null;
    }

    return ApiCallRecord(
      id: json['id'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      method: json['method'] as String,
      url: json['url'] as String,
      endpointTemplate: json['endpointTemplate'] as String,
      requestHeaders: readHeaders(json['requestHeaders']),
      requestBody: json['requestBody'] as String?,
      requestBodySize: (json['requestBodySize'] as num?)?.toInt() ?? 0,
      responseStatus: (json['responseStatus'] as num?)?.toInt(),
      responseHeaders: readHeaders(json['responseHeaders']),
      responseBody: json['responseBody'] as String?,
      responseBodySize: (json['responseBodySize'] as num?)?.toInt() ?? 0,
      timing: json['timing'] is Map
          ? TimingBreakdown.fromJson(json['timing'] as Map)
          : null,
      cancelled: (json['cancelled'] as bool?) ?? false,
      errorKind: _parseErrorKind(json['errorKind']),
      errorMessage: json['errorMessage'] as String?,
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      tag: json['tag'] as String?,
      requestIdHeader: json['requestIdHeader'] as String?,
      authTokenRaw: json['authTokenRaw'] as String?,
      screenName: json['screenName'] as String?,
      previousAttemptId: json['previousAttemptId'] as String?,
    );
  }

  static ErrorKind? _parseErrorKind(dynamic raw) {
    if (raw == null) return null;
    final name = raw.toString();
    for (final v in ErrorKind.values) {
      if (v.name == name) return v;
    }
    return null;
  }

  ApiCallRecord copyWith({
    DateTime? completedAt,
    int? responseStatus,
    Map<String, String>? responseHeaders,
    String? responseBody,
    int? responseBodySize,
    TimingBreakdown? timing,
    bool? cancelled,
    ErrorKind? errorKind,
    String? errorMessage,
    String? requestIdHeader,
  }) {
    return ApiCallRecord(
      id: id,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      method: method,
      url: url,
      endpointTemplate: endpointTemplate,
      requestHeaders: requestHeaders,
      requestBody: requestBody,
      requestBodySize: requestBodySize,
      responseStatus: responseStatus ?? this.responseStatus,
      responseHeaders: responseHeaders ?? this.responseHeaders,
      responseBody: responseBody ?? this.responseBody,
      responseBodySize: responseBodySize ?? this.responseBodySize,
      timing: timing ?? this.timing,
      cancelled: cancelled ?? this.cancelled,
      errorKind: errorKind ?? this.errorKind,
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount,
      tag: tag,
      requestIdHeader: requestIdHeader ?? this.requestIdHeader,
      authTokenRaw: authTokenRaw,
      screenName: screenName,
      previousAttemptId: previousAttemptId,
    );
  }
}
