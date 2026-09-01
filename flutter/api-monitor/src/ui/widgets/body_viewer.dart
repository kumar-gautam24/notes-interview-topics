import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../_palette.dart';

class BodyViewer extends StatefulWidget {
  const BodyViewer({
    super.key,
    required this.title,
    required this.body,
    this.byteSize,
  });

  final String title;
  final String? body;
  final int? byteSize;

  @override
  State<BodyViewer> createState() => _BodyViewerState();
}

class _BodyViewerState extends State<BodyViewer> {
  String _filter = '';
  bool _pretty = true;

  @override
  Widget build(BuildContext context) {
    final body = widget.body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.title, style: MonitorText.heading),
            const SizedBox(width: 8),
            if (widget.byteSize != null)
              Text('· ${formatBytes(widget.byteSize!)}',
                  style: MonitorText.muted),
            const Spacer(),
            if (body != null && body.isNotEmpty) ...[
              IconButton(
                tooltip: _pretty ? 'Show raw' : 'Pretty-print',
                icon: Icon(
                  _pretty ? Icons.code : Icons.auto_awesome_outlined,
                  size: 18,
                  color: MonitorPalette.textSecondary,
                ),
                onPressed: () => setState(() => _pretty = !_pretty),
              ),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy, size: 18,
                    color: MonitorPalette.textSecondary),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: body)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (body == null || body.isEmpty)
          const Text('No body captured.', style: MonitorText.muted)
        else ...[
          TextField(
            onChanged: (v) => setState(() => _filter = v.trim()),
            style: MonitorText.monoSmall,
            decoration: InputDecoration(
              hintText: 'Search in body…',
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MonitorPalette.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: MonitorPalette.border),
            ),
            child: SelectableText(
              _renderBody(body),
              style: MonitorText.mono,
            ),
          ),
        ],
      ],
    );
  }

  String _renderBody(String body) {
    String rendered = body;
    if (_pretty) {
      try {
        final decoded = jsonDecode(body);
        rendered = const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {}
    }
    if (_filter.isEmpty) return rendered;
    final lines = rendered.split('\n');
    final matches = lines
        .where((l) => l.toLowerCase().contains(_filter.toLowerCase()))
        .toList();
    if (matches.isEmpty) return '(no matches for "$_filter")';
    return matches.join('\n');
  }
}
