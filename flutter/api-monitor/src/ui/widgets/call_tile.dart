import 'package:flutter/material.dart';

import '../../model/api_call_record.dart';
import '../_palette.dart';
import 'timing_bar.dart';

/// Collapsible row used in the timeline. Expanding shows the timing waterfall
/// and quick-action buttons. Tapping `Open` (provided by parent via
/// [onOpenDetail]) pushes the full detail screen.
class CallTile extends StatefulWidget {
  const CallTile({
    super.key,
    required this.record,
    required this.onOpenDetail,
    this.alertLatencyMs,
  });

  final ApiCallRecord record;
  final VoidCallback onOpenDetail;
  final int? alertLatencyMs;

  @override
  State<CallTile> createState() => _CallTileState();
}

class _CallTileState extends State<CallTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final statusColor = MonitorPalette.forStatus(r.status);
    final methodColor = MonitorPalette.forMethod(r.method);
    final total = r.timing?.totalMs;
    final isSlow = widget.alertLatencyMs != null &&
        total != null &&
        total > widget.alertLatencyMs!;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: MonitorPalette.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _expanded ? MonitorPalette.accent : MonitorPalette.border,
          width: _expanded ? 1.2 : 1,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        color: MonitorPalette.textSecondary,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(formatTime(r.startedAt),
                          style: MonitorText.monoMuted),
                      const SizedBox(width: 10),
                      _MethodChip(method: r.method, color: methodColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _displayPath(r),
                          style: MonitorText.body,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 26),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (r.isInFlight)
                          const _PulsingDot(color: MonitorPalette.accent)
                        else
                          _Dot(color: statusColor),
                        Text(_statusLabel(r), style: MonitorText.monoSmall),
                        Text('· ${_latencyText(r, total)}',
                            style: MonitorText.muted),
                        if (r.isStuck)
                          Row(mainAxisSize: MainAxisSize.min, children: const [
                            Icon(Icons.hourglass_top,
                                color: MonitorPalette.danger, size: 14),
                            SizedBox(width: 2),
                            Text('stuck',
                                style: TextStyle(
                                  color: MonitorPalette.danger,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                )),
                          ]),
                        if (isSlow && !r.isInFlight)
                          Row(mainAxisSize: MainAxisSize.min, children: const [
                            Icon(Icons.warning_amber_rounded,
                                color: MonitorPalette.warning, size: 14),
                            SizedBox(width: 2),
                            Text('slow', style: MonitorText.muted),
                          ]),
                        if (r.requestBodySize > 0)
                          Text('· ↑${formatBytes(r.requestBodySize)}',
                              style: MonitorText.muted),
                        if (r.responseBodySize > 0)
                          Text('· ↓${formatBytes(r.responseBodySize)}',
                              style: MonitorText.muted),
                        if (r.retryCount > 0)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.replay,
                                color: MonitorPalette.warning, size: 12),
                            const SizedBox(width: 2),
                            Text('retry ${r.retryCount}',
                                style: MonitorText.muted),
                          ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 1,
                    color: MonitorPalette.border,
                    margin: const EdgeInsets.only(bottom: 12),
                  ),
                  if (r.timing != null) ...[
                    const Text('Timing', style: MonitorText.heading),
                    const SizedBox(height: 8),
                    TimingBar(timing: r.timing!),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _OutlineButton(
                        icon: Icons.list_alt_outlined,
                        label: 'Headers',
                        onTap: widget.onOpenDetail,
                      ),
                      _OutlineButton(
                        icon: Icons.code,
                        label: 'Body',
                        onTap: widget.onOpenDetail,
                      ),
                      _OutlineButton(
                        icon: Icons.open_in_new,
                        label: 'Open',
                        onTap: widget.onOpenDetail,
                        primary: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _displayPath(ApiCallRecord r) {
    try {
      final uri = Uri.parse(r.url);
      return uri.path + (uri.hasQuery ? '?${uri.query}' : '');
    } catch (_) {
      return r.url;
    }
  }

  String _statusLabel(ApiCallRecord r) {
    if (r.cancelled) return 'CANCELLED';
    if (r.isInFlight) return 'IN-FLIGHT';
    if (r.errorKind != null && r.responseStatus == null) {
      return r.errorKind!.label.toUpperCase();
    }
    if (r.responseStatus != null) return '${r.responseStatus}';
    return 'UNKNOWN';
  }

  String _latencyText(ApiCallRecord r, int? total) {
    if (r.isInFlight) {
      final ms = DateTime.now().difference(r.startedAt).inMilliseconds;
      return '${formatLatency(ms)} and counting…';
    }
    return formatLatency(total);
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctl,
      builder: (_, _) {
        final alpha = 0.4 + (_ctl.value * 0.6);
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: alpha),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

class _MethodChip extends StatelessWidget {
  const _MethodChip({required this.method, required this.color});
  final String method;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        method,
        style: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final color = primary ? MonitorPalette.accent : MonitorPalette.textPrimary;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: primary ? MonitorPalette.accent : MonitorPalette.border),
          borderRadius: BorderRadius.circular(6),
          color: primary
              ? MonitorPalette.accent.withValues(alpha: 0.10)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

