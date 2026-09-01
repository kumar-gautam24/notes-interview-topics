import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../_palette.dart';

class KvTable extends StatelessWidget {
  const KvTable({
    super.key,
    required this.title,
    required this.entries,
    this.emptyMessage = 'No entries.',
  });

  final String title;
  final Map<String, String> entries;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: MonitorText.heading),
            const Spacer(),
            if (entries.isNotEmpty)
              IconButton(
                tooltip: 'Copy as JSON',
                onPressed: () {
                  final lines = entries.entries
                      .map((e) => '"${e.key}": "${e.value}"')
                      .join(',\n  ');
                  Clipboard.setData(ClipboardData(text: '{\n  $lines\n}'));
                },
                icon: const Icon(Icons.copy_all_outlined,
                    color: MonitorPalette.textSecondary, size: 18),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Text(emptyMessage, style: MonitorText.muted)
        else
          Container(
            decoration: BoxDecoration(
              color: MonitorPalette.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: MonitorPalette.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++)
                  _row(entries.entries.elementAt(i),
                      isLast: i == entries.length - 1),
              ],
            ),
          ),
      ],
    );
  }

  Widget _row(MapEntry<String, String> e, {required bool isLast}) {
    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: MonitorPalette.border, width: 1),
              ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: SelectableText(e.key, style: MonitorText.monoMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 7,
            child: SelectableText(e.value, style: MonitorText.monoSmall),
          ),
        ],
      ),
    );
  }
}
