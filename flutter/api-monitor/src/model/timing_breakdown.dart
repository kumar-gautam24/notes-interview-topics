/// Timing breakdown of a single HTTP call.
///
/// v1 captures three reliable stages from Dio interceptor events:
///   - [waitMs]:     request start  →  first response byte (TTFB)
///   - [downloadMs]: first response byte → response complete
///   - [totalMs]:    request start  →  request complete
///
/// DNS / TCP / TLS sub-stages are intentionally omitted in v1 because they
/// require wrapping `HttpClientAdapter` and the gain is small relative to
/// the integration risk. Fields are reserved as nullable for future use.
class TimingBreakdown {
  const TimingBreakdown({
    required this.totalMs,
    this.waitMs,
    this.downloadMs,
    this.dnsMs,
    this.connectMs,
    this.tlsMs,
  });

  final int totalMs;
  final int? waitMs;
  final int? downloadMs;
  final int? dnsMs;
  final int? connectMs;
  final int? tlsMs;

  Map<String, dynamic> toJson() => {
        'totalMs': totalMs,
        if (waitMs != null) 'waitMs': waitMs,
        if (downloadMs != null) 'downloadMs': downloadMs,
        if (dnsMs != null) 'dnsMs': dnsMs,
        if (connectMs != null) 'connectMs': connectMs,
        if (tlsMs != null) 'tlsMs': tlsMs,
      };

  factory TimingBreakdown.fromJson(Map<dynamic, dynamic> json) =>
      TimingBreakdown(
        totalMs: (json['totalMs'] as num?)?.toInt() ?? 0,
        waitMs: (json['waitMs'] as num?)?.toInt(),
        downloadMs: (json['downloadMs'] as num?)?.toInt(),
        dnsMs: (json['dnsMs'] as num?)?.toInt(),
        connectMs: (json['connectMs'] as num?)?.toInt(),
        tlsMs: (json['tlsMs'] as num?)?.toInt(),
      );
}
