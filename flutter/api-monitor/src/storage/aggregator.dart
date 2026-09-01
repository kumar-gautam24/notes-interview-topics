import '../model/api_call_record.dart';

/// Per-endpoint aggregate row. Computed on demand from a list of records.
class EndpointAggregate {
  EndpointAggregate({
    required this.method,
    required this.endpointTemplate,
    required this.calls,
    required this.errors,
    required this.p50Ms,
    required this.p95Ms,
    required this.p99Ms,
    required this.lastAt,
  });

  final String method;
  final String endpointTemplate;
  final int calls;
  final int errors;
  final int? p50Ms;
  final int? p95Ms;
  final int? p99Ms;
  final DateTime? lastAt;

  double get errorRate => calls == 0 ? 0 : errors / calls;

  String get key => '$method $endpointTemplate';
}

class Aggregator {
  const Aggregator();

  /// Group records by `method + endpointTemplate` and compute counts and
  /// percentiles. O(N log N) due to per-group sort; fine for N ≤ a few
  /// thousand which is well above our retention cap.
  List<EndpointAggregate> aggregate(List<ApiCallRecord> records) {
    final groups = <String, List<ApiCallRecord>>{};
    for (final r in records) {
      final key = '${r.method} ${r.endpointTemplate}';
      groups.putIfAbsent(key, () => <ApiCallRecord>[]).add(r);
    }
    final out = <EndpointAggregate>[];
    groups.forEach((key, group) {
      final method = group.first.method;
      final tmpl = group.first.endpointTemplate;
      final latencies = <int>[];
      var errors = 0;
      DateTime? last;
      for (final r in group) {
        if (r.isError) errors++;
        final t = r.timing?.totalMs;
        if (t != null) latencies.add(t);
        if (last == null || r.startedAt.isAfter(last)) last = r.startedAt;
      }
      latencies.sort();
      out.add(
        EndpointAggregate(
          method: method,
          endpointTemplate: tmpl,
          calls: group.length,
          errors: errors,
          p50Ms: _percentile(latencies, 0.50),
          p95Ms: _percentile(latencies, 0.95),
          p99Ms: _percentile(latencies, 0.99),
          lastAt: last,
        ),
      );
    });
    return out;
  }

  static int? _percentile(List<int> sorted, double p) {
    if (sorted.isEmpty) return null;
    if (sorted.length == 1) return sorted.first;
    final rank = (p * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
    return sorted[rank];
  }
}
