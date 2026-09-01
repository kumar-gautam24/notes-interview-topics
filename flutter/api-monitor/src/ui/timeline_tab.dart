import 'package:flutter/material.dart';

import '../core/api_monitor.dart';
import '../matching/endpoint_matcher.dart';
import '../model/api_call_record.dart';
import '_palette.dart';
import 'call_detail_screen.dart';
import 'widgets/call_tile.dart';
import 'widgets/filter_bar.dart';

class TimelineTab extends StatefulWidget {
  const TimelineTab({
    super.key,
    this.initialFilter = const TimelineFilter(),
    this.lockErrorsOnly = false,
  });

  final TimelineFilter initialFilter;
  final bool lockErrorsOnly;

  @override
  State<TimelineTab> createState() => _TimelineTabState();
}

class _TimelineTabState extends State<TimelineTab> {
  late TimelineFilter _filter;
  static const _matcher = EndpointMatcher();

  @override
  void initState() {
    super.initState();
    _filter = widget.lockErrorsOnly
        ? widget.initialFilter.copyWith(errorsOnly: true)
        : widget.initialFilter;
  }

  @override
  Widget build(BuildContext context) {
    final monitor = ApiMonitor.instance;
    return StreamBuilder<void>(
      stream: monitor.store.changesDebounced,
      builder: (context, _) {
        final all = monitor.store.all();
        final filtered = _apply(all, _filter);
        return Column(
          children: [
            FilterBar(
              value: _filter,
              onChanged: (v) => setState(() => _filter = v),
            ),
            if (filtered.isNotEmpty) _exportRow(context, filtered),
            Expanded(
              child: filtered.isEmpty
                  ? _empty(all.isEmpty)
                  : ListView.builder(
                      itemCount: filtered.length,
                      padding: const EdgeInsets.only(top: 4, bottom: 24),
                      itemBuilder: (_, i) {
                        final r = filtered[i];
                        final rule = _matcher.findRule(
                            Uri.parse(r.url).path, monitor.configStore.current);
                        return Dismissible(
                          key: ValueKey('api-call-${r.id}'),
                          direction: DismissDirection.endToStart,
                          background: _deleteBackground(),
                          onDismissed: (_) {
                            ApiMonitor.instance.store.delete(r.id);
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                duration: const Duration(seconds: 2),
                                content: Text(
                                    'Deleted ${r.method} ${r.endpointTemplate}'),
                              ),
                            );
                          },
                          child: CallTile(
                            record: r,
                            alertLatencyMs: rule?.alertLatencyMs,
                            onOpenDetail: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      CallDetailScreen(recordId: r.id),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _exportRow(BuildContext context, List<ApiCallRecord> records) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: 8,
        children: [
          Text('${records.length} visible', style: MonitorText.muted),
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ApiMonitor.instance.exporter.shareJson(
                  records: records,
                  filenameHint: 'api-monitor-filtered',
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Export failed: $e')),
                );
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.ios_share,
                      size: 14, color: MonitorPalette.accent),
                  SizedBox(width: 4),
                  Text('Export visible',
                      style: TextStyle(
                        color: MonitorPalette.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deleteBackground() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerRight,
      decoration: BoxDecoration(
        color: MonitorPalette.danger.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: MonitorPalette.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.delete_outline, color: MonitorPalette.danger, size: 18),
          SizedBox(width: 6),
          Text('Delete',
              style: TextStyle(
                color: MonitorPalette.danger,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }

  Widget _empty(bool isStoreEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox_outlined,
                color: MonitorPalette.textSecondary, size: 48),
            const SizedBox(height: 12),
            Text(
              isStoreEmpty
                  ? 'No API calls captured yet.'
                  : 'No calls match the current filter.',
              style: MonitorText.muted,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  List<ApiCallRecord> _apply(
      List<ApiCallRecord> records, TimelineFilter f) {
    final cutoff = DateTime.now().subtract(f.timeWindow.duration);
    final search = f.search.toLowerCase();
    return records.where((r) {
      if (r.startedAt.isBefore(cutoff)) return false;
      if (widget.lockErrorsOnly && !r.isError) return false;
      if (f.errorsOnly && !r.isError) return false;
      if (f.templateExact != null && r.endpointTemplate != f.templateExact) {
        return false;
      }
      if (f.methods.isNotEmpty && !f.methods.contains(r.method)) return false;
      if (f.statusBuckets.isNotEmpty) {
        final code = r.responseStatus;
        var match = false;
        for (final b in f.statusBuckets) {
          switch (b) {
            case StatusBucket.success:
              if (code != null && code >= 200 && code < 300) match = true;
              break;
            case StatusBucket.redirect:
              if (code != null && code >= 300 && code < 400) match = true;
              break;
            case StatusBucket.clientError:
              if (code != null && code >= 400 && code < 500) match = true;
              break;
            case StatusBucket.serverError:
              if (code != null && code >= 500) match = true;
              break;
            case StatusBucket.error:
              if (r.errorKind != null || r.cancelled) match = true;
              break;
          }
        }
        if (!match) return false;
      }
      if (search.isNotEmpty) {
        final hay = '${r.url} ${r.requestBody ?? ''} ${r.responseBody ?? ''}'
            .toLowerCase();
        if (!hay.contains(search)) return false;
      }
      return true;
    }).toList();
  }
}
