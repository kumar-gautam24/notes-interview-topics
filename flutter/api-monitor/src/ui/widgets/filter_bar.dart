import 'package:flutter/material.dart';

import '../_palette.dart';

class TimelineFilter {
  const TimelineFilter({
    this.search = '',
    this.methods = const {},
    this.statusBuckets = const {},
    this.timeWindow = TimeWindow.all,
    this.errorsOnly = false,
    this.templateExact,
  });

  final String search;
  final Set<String> methods;
  final Set<StatusBucket> statusBuckets;
  final TimeWindow timeWindow;
  final bool errorsOnly;

  /// When set, only records whose `endpointTemplate` equals this string
  /// are kept. Used by the Endpoints tab drill-down so a row for
  /// `/profile/{id}` lists every actual call regardless of concrete id.
  final String? templateExact;

  TimelineFilter copyWith({
    String? search,
    Set<String>? methods,
    Set<StatusBucket>? statusBuckets,
    TimeWindow? timeWindow,
    bool? errorsOnly,
    String? templateExact,
  }) {
    return TimelineFilter(
      search: search ?? this.search,
      methods: methods ?? this.methods,
      statusBuckets: statusBuckets ?? this.statusBuckets,
      timeWindow: timeWindow ?? this.timeWindow,
      errorsOnly: errorsOnly ?? this.errorsOnly,
      templateExact: templateExact ?? this.templateExact,
    );
  }
}

enum StatusBucket { success, redirect, clientError, serverError, error }

enum TimeWindow {
  oneMin('1m', Duration(minutes: 1)),
  fiveMin('5m', Duration(minutes: 5)),
  thirtyMin('30m', Duration(minutes: 30)),
  all('All', Duration(days: 36500));

  const TimeWindow(this.label, this.duration);
  final String label;
  final Duration duration;
}

class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.value,
    required this.onChanged,
    this.showErrorsOnlyToggle = true,
  });

  final TimelineFilter value;
  final ValueChanged<TimelineFilter> onChanged;
  final bool showErrorsOnlyToggle;

  static const _methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: MonitorPalette.bgDark,
        border: Border(
          bottom: BorderSide(color: MonitorPalette.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            onChanged: (v) => onChanged(value.copyWith(search: v.trim())),
            style: MonitorText.body,
            decoration: InputDecoration(
              hintText: 'Search URL or body…',
              hintStyle: MonitorText.muted,
              isDense: true,
              filled: true,
              fillColor: MonitorPalette.surface,
              prefixIcon: const Icon(Icons.search,
                  color: MonitorPalette.textSecondary, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: MonitorPalette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: MonitorPalette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: MonitorPalette.accent),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final m in _methods)
                  _Chip(
                    label: m,
                    selected: value.methods.contains(m),
                    color: MonitorPalette.forMethod(m),
                    onTap: () {
                      final next = {...value.methods};
                      next.contains(m) ? next.remove(m) : next.add(m);
                      onChanged(value.copyWith(methods: next));
                    },
                  ),
                const SizedBox(width: 12),
                _Chip(
                  label: '2xx',
                  selected: value.statusBuckets.contains(StatusBucket.success),
                  color: MonitorPalette.success,
                  onTap: () => _toggleStatus(StatusBucket.success),
                ),
                _Chip(
                  label: '4xx',
                  selected:
                      value.statusBuckets.contains(StatusBucket.clientError),
                  color: MonitorPalette.warning,
                  onTap: () => _toggleStatus(StatusBucket.clientError),
                ),
                _Chip(
                  label: '5xx',
                  selected:
                      value.statusBuckets.contains(StatusBucket.serverError),
                  color: MonitorPalette.danger,
                  onTap: () => _toggleStatus(StatusBucket.serverError),
                ),
                _Chip(
                  label: 'err',
                  selected: value.statusBuckets.contains(StatusBucket.error),
                  color: MonitorPalette.danger,
                  onTap: () => _toggleStatus(StatusBucket.error),
                ),
                const SizedBox(width: 12),
                for (final w in TimeWindow.values)
                  _Chip(
                    label: w.label,
                    selected: value.timeWindow == w,
                    color: MonitorPalette.accent,
                    onTap: () => onChanged(value.copyWith(timeWindow: w)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleStatus(StatusBucket b) {
    final next = {...value.statusBuckets};
    next.contains(b) ? next.remove(b) : next.add(b);
    onChanged(value.copyWith(statusBuckets: next));
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color:
                selected ? color.withValues(alpha: 0.18) : MonitorPalette.surface,
            border: Border.all(
              color: selected ? color : MonitorPalette.border,
              width: selected ? 1.2 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? color : MonitorPalette.textSecondary,
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
