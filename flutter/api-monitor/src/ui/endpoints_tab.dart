import 'package:flutter/material.dart';

import '../core/api_monitor.dart';
import '../storage/aggregator.dart';
import '_palette.dart';
import 'timeline_tab.dart';
import 'widgets/filter_bar.dart';

enum _SortKey { calls, p95, errorRate, recent }

class EndpointsTab extends StatefulWidget {
  const EndpointsTab({super.key});

  @override
  State<EndpointsTab> createState() => _EndpointsTabState();
}

class _EndpointsTabState extends State<EndpointsTab> {
  _SortKey _sort = _SortKey.recent;
  static const _aggregator = Aggregator();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: ApiMonitor.instance.store.changesDebounced,
      builder: (context, _) {
        final records = ApiMonitor.instance.store.all();
        final aggs = _aggregator.aggregate(records);
        _sortAggs(aggs);
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: const BoxDecoration(
                color: MonitorPalette.bgDark,
                border: Border(
                  bottom: BorderSide(color: MonitorPalette.border, width: 1),
                ),
              ),
              child: Row(
                children: [
                  const Text('Sort by', style: MonitorText.muted),
                  const SizedBox(width: 8),
                  for (final k in _SortKey.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(_sortLabel(k),
                            style: const TextStyle(fontSize: 11)),
                        selected: _sort == k,
                        onSelected: (_) => setState(() => _sort = k),
                        backgroundColor: MonitorPalette.surface,
                        selectedColor:
                            MonitorPalette.accent.withValues(alpha: 0.2),
                        side: BorderSide(
                          color: _sort == k
                              ? MonitorPalette.accent
                              : MonitorPalette.border,
                        ),
                        labelStyle: TextStyle(
                          color: _sort == k
                              ? MonitorPalette.accent
                              : MonitorPalette.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: aggs.isEmpty
                  ? const Center(
                      child: Text('No endpoints captured yet.',
                          style: MonitorText.muted),
                    )
                  : ListView.builder(
                      itemCount: aggs.length,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemBuilder: (_, i) => _AggRow(
                        agg: aggs[i],
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => Theme(
                                data: ThemeData.dark(useMaterial3: true).copyWith(
                                  scaffoldBackgroundColor:
                                      MonitorPalette.bgDark,
                                  appBarTheme: const AppBarTheme(
                                    backgroundColor: MonitorPalette.bgDark,
                                    foregroundColor: MonitorPalette.textPrimary,
                                    elevation: 0,
                                  ),
                                ),
                                child: Scaffold(
                                  appBar: AppBar(
                                    title: Text(
                                      '${aggs[i].method} ${aggs[i].endpointTemplate}',
                                      style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 14),
                                    ),
                                  ),
                                  body: TimelineTab(
                                    initialFilter: TimelineFilter(
                                      methods: {aggs[i].method},
                                      templateExact:
                                          aggs[i].endpointTemplate,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  String _sortLabel(_SortKey k) => switch (k) {
        _SortKey.calls => 'calls',
        _SortKey.p95 => 'P95',
        _SortKey.errorRate => 'errors',
        _SortKey.recent => 'recent',
      };

  void _sortAggs(List<EndpointAggregate> aggs) {
    switch (_sort) {
      case _SortKey.calls:
        aggs.sort((a, b) => b.calls.compareTo(a.calls));
        break;
      case _SortKey.p95:
        aggs.sort((a, b) => (b.p95Ms ?? 0).compareTo(a.p95Ms ?? 0));
        break;
      case _SortKey.errorRate:
        aggs.sort((a, b) => b.errorRate.compareTo(a.errorRate));
        break;
      case _SortKey.recent:
        aggs.sort(
            (a, b) => (b.lastAt ?? DateTime(0)).compareTo(a.lastAt ?? DateTime(0)));
        break;
    }
  }
}

class _AggRow extends StatelessWidget {
  const _AggRow({required this.agg, required this.onTap});

  final EndpointAggregate agg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final methodColor = MonitorPalette.forMethod(agg.method);
    final errorPct = (agg.errorRate * 100).toStringAsFixed(0);
    final errorColor = agg.errorRate == 0
        ? MonitorPalette.success
        : agg.errorRate > 0.1
            ? MonitorPalette.danger
            : MonitorPalette.warning;
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: MonitorPalette.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MonitorPalette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: methodColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    agg.method,
                    style: TextStyle(
                      color: methodColor,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    agg.endpointTemplate,
                    style: MonitorText.body,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(formatRelative(agg.lastAt), style: MonitorText.muted),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 0),
              child: Row(
                children: [
                  _Stat(label: 'calls', value: '${agg.calls}'),
                  _Stat(
                    label: 'errors',
                    value: '$errorPct%',
                    color: errorColor,
                  ),
                  _Stat(label: 'p50', value: formatLatency(agg.p50Ms)),
                  _Stat(label: 'p95', value: formatLatency(agg.p95Ms)),
                  _Stat(label: 'p99', value: formatLatency(agg.p99Ms)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: MonitorText.muted),
          const SizedBox(height: 1),
          Text(
            value,
            style: MonitorText.monoSmall.copyWith(
              color: color ?? MonitorPalette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
