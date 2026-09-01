import 'package:flutter/material.dart';

import '../core/api_monitor.dart';
import '../core/monitor_config.dart';
import '../model/endpoint_rule.dart';
import '_palette.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MonitorConfig>(
      stream: ApiMonitor.instance.configStore.changes,
      initialData: ApiMonitor.instance.configStore.current,
      builder: (context, snap) {
        final cfg = snap.data ?? const MonitorConfig();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('Master', [
              _switchTile(
                'Monitoring enabled',
                'Master kill switch for capture.',
                cfg.enabled,
                (v) => _save(cfg.copyWith(enabled: v)),
              ),
              _switchTile(
                'Paused',
                'Stop capturing new calls. Existing log stays available.',
                cfg.paused,
                (v) => _save(cfg.copyWith(paused: v)),
              ),
            ]),
            const SizedBox(height: 16),
            _section('Capture', [
              _switchTile(
                'Request headers',
                null,
                cfg.capture.requestHeaders,
                (v) => _save(cfg.copyWith(
                    capture: cfg.capture.copyWith(requestHeaders: v))),
              ),
              _switchTile(
                'Request body',
                null,
                cfg.capture.requestBody,
                (v) => _save(cfg.copyWith(
                    capture: cfg.capture.copyWith(requestBody: v))),
              ),
              _switchTile(
                'Response headers',
                null,
                cfg.capture.responseHeaders,
                (v) => _save(cfg.copyWith(
                    capture: cfg.capture.copyWith(responseHeaders: v))),
              ),
              _switchTile(
                'Response body',
                null,
                cfg.capture.responseBody,
                (v) => _save(cfg.copyWith(
                    capture: cfg.capture.copyWith(responseBody: v))),
              ),
              _switchTile(
                'Timing',
                null,
                cfg.capture.timing,
                (v) => _save(cfg.copyWith(
                    capture: cfg.capture.copyWith(timing: v))),
              ),
            ]),
            const SizedBox(height: 16),
            _section('Retention', [
              _sliderTile(
                'Max records',
                cfg.retention.maxRecords.toDouble(),
                100,
                5000,
                (v) => _save(cfg.copyWith(
                    retention:
                        cfg.retention.copyWith(maxRecords: v.round()))),
                valueLabel: '${cfg.retention.maxRecords}',
              ),
              _sliderTile(
                'Max body bytes',
                cfg.retention.maxBodyBytes.toDouble(),
                1024,
                256 * 1024,
                (v) => _save(cfg.copyWith(
                    retention:
                        cfg.retention.copyWith(maxBodyBytes: v.round()))),
                valueLabel: formatBytes(cfg.retention.maxBodyBytes),
              ),
              _sliderTile(
                'TTL (days)',
                cfg.retention.ttlDays.toDouble(),
                1,
                30,
                (v) => _save(cfg.copyWith(
                    retention: cfg.retention.copyWith(ttlDays: v.round()))),
                valueLabel: '${cfg.retention.ttlDays}d',
              ),
            ]),
            const SizedBox(height: 16),
            _section('Endpoint rules', [
              _rulesEditor(cfg),
            ]),
            const SizedBox(height: 16),
            _section('Redaction', [
              _ListEditor(
                label: 'Header denylist',
                items: cfg.redaction.headerDenylist,
                onChanged: (list) => _save(cfg.copyWith(
                    redaction:
                        cfg.redaction.copyWith(headerDenylist: list))),
              ),
              _ListEditor(
                label: 'Body JSON keys',
                items: cfg.redaction.bodyJsonKeys,
                onChanged: (list) => _save(cfg.copyWith(
                    redaction:
                        cfg.redaction.copyWith(bodyJsonKeys: list))),
              ),
              _ListEditor(
                label: 'URL query params',
                items: cfg.redaction.urlQueryDenylist,
                onChanged: (list) => _save(cfg.copyWith(
                    redaction:
                        cfg.redaction.copyWith(urlQueryDenylist: list))),
              ),
            ]),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _confirmClear,
              icon: const Icon(Icons.delete_outline,
                  color: MonitorPalette.danger),
              label: const Text('Clear all logs',
                  style: TextStyle(color: MonitorPalette.danger)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: MonitorPalette.danger),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _save(MonitorConfig next) =>
      ApiMonitor.instance.updateConfig(next);

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: MonitorPalette.surface,
        title: const Text('Clear all logs?',
            style: TextStyle(color: MonitorPalette.textPrimary)),
        content: const Text('This deletes every captured call. Cannot be undone.',
            style: TextStyle(color: MonitorPalette.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear',
                style: TextStyle(color: MonitorPalette.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ApiMonitor.instance.clearLogs();
    }
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: MonitorPalette.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MonitorPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Text(title.toUpperCase(),
                style: MonitorText.muted.copyWith(
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                )),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _switchTile(
    String label,
    String? subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: MonitorText.body),
                if (subtitle != null)
                  Text(subtitle, style: MonitorText.muted),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: MonitorPalette.accent,
          ),
        ],
      ),
    );
  }

  Widget _sliderTile(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    required String valueLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: MonitorText.body)),
              Text(valueLabel,
                  style: MonitorText.monoSmall.copyWith(
                      color: MonitorPalette.accent,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
            activeColor: MonitorPalette.accent,
          ),
        ],
      ),
    );
  }

  Widget _rulesEditor(MonitorConfig cfg) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cfg.endpointRules.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                  'No rules. Add a glob pattern to override capture for matching paths.',
                  style: MonitorText.muted),
            ),
          for (final rule in cfg.endpointRules.values)
            _RuleRow(
              rule: rule,
              onChanged: (next) {
                final rules = {...cfg.endpointRules};
                rules.remove(rule.pattern);
                rules[next.pattern] = next;
                _save(cfg.copyWith(endpointRules: rules));
              },
              onRemove: () {
                final rules = {...cfg.endpointRules}..remove(rule.pattern);
                _save(cfg.copyWith(endpointRules: rules));
              },
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _showAddRuleDialog(cfg),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add rule'),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: MonitorPalette.border),
              foregroundColor: MonitorPalette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddRuleDialog(MonitorConfig cfg) async {
    final controller = TextEditingController();
    final pattern = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: MonitorPalette.surface,
        title: const Text('Add endpoint rule',
            style: TextStyle(color: MonitorPalette.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: MonitorText.mono,
          decoration: const InputDecoration(
            hintText: 'e.g. /wearables/**',
            hintStyle: MonitorText.muted,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (pattern == null || pattern.isEmpty) return;
    if (cfg.endpointRules.containsKey(pattern)) return;
    final rules = {
      ...cfg.endpointRules,
      pattern: EndpointRule(pattern: pattern),
    };
    await _save(cfg.copyWith(endpointRules: rules));
  }
}

/// Stateful list editor — owns its own [TextEditingController] so that
/// the input keeps focus across parent rebuilds (e.g. when a sibling
/// switch is toggled and the surrounding `StreamBuilder<MonitorConfig>`
/// rebuilds the whole settings tree).
class _ListEditor extends StatefulWidget {
  const _ListEditor({
    required this.label,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final List<String> items;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends State<_ListEditor> {
  late final TextEditingController _controller = TextEditingController();
  late final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _add() {
    final value = _controller.text.trim();
    if (value.isEmpty || widget.items.contains(value)) return;
    widget.onChanged([...widget.items, value]);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: MonitorText.body),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in widget.items)
                _Tag(
                  label: item,
                  onRemove: () => widget.onChanged(
                    widget.items
                        .where((e) => e != item)
                        .toList(growable: false),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: MonitorText.monoSmall,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    hintText: 'Add…',
                    hintStyle: MonitorText.muted,
                    isDense: true,
                    filled: true,
                    fillColor: MonitorPalette.bgDark,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide:
                          const BorderSide(color: MonitorPalette.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide:
                          const BorderSide(color: MonitorPalette.border),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline,
                    color: MonitorPalette.accent),
                onPressed: _add,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      decoration: BoxDecoration(
        color: MonitorPalette.bgDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MonitorPalette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: MonitorText.monoSmall),
          IconButton(
            icon: const Icon(Icons.close,
                size: 14, color: MonitorPalette.textSecondary),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.rule,
    required this.onChanged,
    required this.onRemove,
  });

  final EndpointRule rule;
  final ValueChanged<EndpointRule> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: MonitorPalette.bgDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MonitorPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(rule.pattern, style: MonitorText.mono)),
              Switch.adaptive(
                value: rule.enabled,
                onChanged: (v) => onChanged(rule.copyWith(enabled: v)),
                activeThumbColor: MonitorPalette.accent,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: MonitorPalette.textSecondary),
                onPressed: onRemove,
              ),
            ],
          ),
          if (rule.alertLatencyMs != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Alert > ${rule.alertLatencyMs}ms',
                style: MonitorText.muted,
              ),
            ),
        ],
      ),
    );
  }
}
