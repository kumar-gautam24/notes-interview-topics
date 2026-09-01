import 'package:flutter/material.dart';

import '../../model/timing_breakdown.dart';
import '../_palette.dart';

class TimingBar extends StatelessWidget {
  const TimingBar({super.key, required this.timing});

  final TimingBreakdown timing;

  @override
  Widget build(BuildContext context) {
    final stages = <(_StageLabel, int?)>[
      (_StageLabel.dns, timing.dnsMs),
      (_StageLabel.connect, timing.connectMs),
      (_StageLabel.tls, timing.tlsMs),
      (_StageLabel.wait, timing.waitMs),
      (_StageLabel.download, timing.downloadMs),
    ];
    final hasDetail = stages.any((s) => s.$2 != null);
    final maxValue = hasDetail
        ? stages.map((s) => s.$2 ?? 0).fold<int>(0, (a, b) => a > b ? a : b)
        : timing.totalMs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasDetail)
          for (final s in stages)
            if (s.$2 != null)
              _StageRow(label: s.$1.label, ms: s.$2!, max: maxValue, color: s.$1.color),
        if (!hasDetail)
          _StageRow(
            label: 'Total',
            ms: timing.totalMs,
            max: maxValue == 0 ? 1 : maxValue,
            color: MonitorPalette.accent,
          ),
        if (hasDetail) ...[
          const SizedBox(height: 4),
          Container(
            height: 1,
            color: MonitorPalette.border,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(
                width: 84,
                child: Text('Total', style: MonitorText.body),
              ),
              Text(formatLatency(timing.totalMs),
                  style: MonitorText.body.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ],
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.label,
    required this.ms,
    required this.max,
    required this.color,
  });

  final String label;
  final int ms;
  final int max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ratio = max == 0 ? 0.0 : (ms / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(label, style: MonitorText.muted),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Stack(
                children: [
                  Container(
                    height: 8,
                    color: MonitorPalette.surfaceAlt,
                  ),
                  FractionallySizedBox(
                    widthFactor: ratio,
                    child: Container(
                      height: 8,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              formatLatency(ms),
              style: MonitorText.monoSmall,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

enum _StageLabel {
  dns('DNS', Color(0xFF8E6FE0)),
  connect('Connect', Color(0xFF61AFFE)),
  tls('TLS', Color(0xFF50E3C2)),
  wait('Wait (TTFB)', Color(0xFFFFC542)),
  download('Download', Color(0xFF49CC90));

  const _StageLabel(this.label, this.color);
  final String label;
  final Color color;
}
