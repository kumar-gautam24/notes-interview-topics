import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_monitor.dart';
import '../model/api_call_record.dart';
import '_palette.dart';
import 'widgets/body_viewer.dart';
import 'widgets/kv_table.dart';
import 'widgets/timing_bar.dart';

class CallDetailScreen extends StatelessWidget {
  const CallDetailScreen({super.key, required this.recordId});

  final String recordId;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: MonitorPalette.bgDark,
        appBarTheme: const AppBarTheme(
          backgroundColor: MonitorPalette.bgDark,
          foregroundColor: MonitorPalette.textPrimary,
          elevation: 0,
        ),
      ),
      child: StreamBuilder<void>(
        stream: ApiMonitor.instance.store.changes,
        builder: (context, _) {
          final record = ApiMonitor.instance.store.get(recordId);
          if (record == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Call detail')),
              body: const Center(
                child: Text('Record no longer in store',
                    style: MonitorText.muted),
              ),
            );
          }
          return _Body(record: record);
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.record});

  final ApiCallRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final statusColor = MonitorPalette.forStatus(r.status);
    final methodColor = MonitorPalette.forMethod(r.method);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Call detail'),
        actions: [
          IconButton(
            tooltip: 'Copy as cURL',
            icon: const Icon(Icons.terminal),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _buildCurl(r)));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('cURL copied')),
              );
            },
          ),
          IconButton(
            tooltip: 'Share as JSON',
            icon: const Icon(Icons.ios_share),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ApiMonitor.instance.exporter.shareJson(
                  records: [r],
                  filenameHint: 'api-call',
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Share failed: $e')),
                );
              }
            },
          ),
          if (ApiMonitor.instance.hostDio != null)
            IconButton(
              tooltip: 'Replay request',
              icon: const Icon(Icons.replay),
              onPressed: () => _replay(context, r),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              record: r,
              statusColor: statusColor,
              methodColor: methodColor,
            ),
            const SizedBox(height: 16),
            if (r.timing != null) ...[
              const Text('Timing', style: MonitorText.heading),
              const SizedBox(height: 8),
              TimingBar(timing: r.timing!),
              const SizedBox(height: 20),
            ],
            if (r.authTokenRaw != null) ...[
              _AuthTokenPanel(token: r.authTokenRaw!),
              const SizedBox(height: 20),
            ],
            KvTable(
              title: 'Request headers',
              entries: r.requestHeaders ?? const {},
              emptyMessage: 'Capture disabled or empty.',
            ),
            const SizedBox(height: 20),
            BodyViewer(
              title: 'Request body',
              body: r.requestBody,
              byteSize: r.requestBodySize,
            ),
            const SizedBox(height: 20),
            KvTable(
              title: 'Response headers',
              entries: r.responseHeaders ?? const {},
              emptyMessage: 'Capture disabled or empty.',
            ),
            const SizedBox(height: 20),
            BodyViewer(
              title: 'Response body',
              body: r.responseBody,
              byteSize: r.responseBodySize,
            ),
            if (r.errorMessage != null) ...[
              const SizedBox(height: 20),
              const Text('Error', style: MonitorText.heading),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: MonitorPalette.danger.withValues(alpha: 0.10),
                  border: Border.all(
                      color: MonitorPalette.danger.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  r.errorMessage!,
                  style: MonitorText.mono.copyWith(color: MonitorPalette.danger),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _replay(BuildContext context, ApiCallRecord r) async {
    final dio = ApiMonitor.instance.hostDio;
    if (dio == null) return;
    final messenger = ScaffoldMessenger.of(context);

    final headers = <String, dynamic>{...?r.requestHeaders};
    // Use the captured raw token if present (the redacted map only has
    // a masked Authorization). Anything else stays as-is.
    if (r.authTokenRaw != null) {
      headers['Authorization'] = r.authTokenRaw;
    }

    Uri parsed;
    try {
      parsed = Uri.parse(r.url);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Bad URL')));
      return;
    }

    messenger.showSnackBar(
      const SnackBar(
          duration: Duration(seconds: 1), content: Text('Replaying…')),
    );

    try {
      final response = await dio.fetch<dynamic>(
        RequestOptions(
          method: r.method,
          path: parsed.toString(),
          headers: headers,
          data: r.requestBody,
          extra: {'monitor.tag': 'replay'},
        ),
      );
      messenger.showSnackBar(
        SnackBar(content: Text('Replay ${response.statusCode}')),
      );
    } on DioException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              'Replay failed: ${e.response?.statusCode ?? e.type.name}'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Replay error: $e')),
      );
    }
  }

  String _buildCurl(ApiCallRecord r) {
    final sb = StringBuffer('curl -X ${r.method} ');
    sb.write("'${r.url}' ");
    final headers = r.requestHeaders;
    if (headers != null) {
      headers.forEach((k, v) {
        sb.write("\\\n  -H '$k: $v' ");
      });
    }
    if (r.requestBody != null && r.requestBody!.isNotEmpty) {
      final escaped = r.requestBody!.replaceAll("'", r"'\''");
      sb.write("\\\n  --data '$escaped'");
    }
    return sb.toString();
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.record,
    required this.statusColor,
    required this.methodColor,
  });

  final ApiCallRecord record;
  final Color statusColor;
  final Color methodColor;

  @override
  Widget build(BuildContext context) {
    final r = record;
    return Container(
      padding: const EdgeInsets.all(14),
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
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: methodColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  r.method,
                  style: TextStyle(
                    color: methodColor,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _statusLabel(r),
                  style: TextStyle(
                    color: statusColor,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Text(formatLatency(r.timing?.totalMs),
                  style: MonitorText.mono.copyWith(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(r.url, style: MonitorText.mono),
          const SizedBox(height: 8),
          Row(
            children: [
              _SizeBadge(
                  label: '↑ Request',
                  size: r.requestBodySize,
                  color: MonitorPalette.forMethod(r.method)),
              const SizedBox(width: 8),
              _SizeBadge(
                  label: '↓ Response',
                  size: r.responseBodySize,
                  color: MonitorPalette.accent),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text('Started ${formatTime(r.startedAt)}',
                  style: MonitorText.muted),
              if (r.completedAt != null)
                Text('· Done ${formatTime(r.completedAt!)}',
                    style: MonitorText.muted),
              if (r.requestIdHeader != null)
                Text('· x-request-id: ${r.requestIdHeader}',
                    style: MonitorText.muted),
              if (r.screenName != null)
                Text('· screen: ${r.screenName}', style: MonitorText.muted),
              if (r.tag != null)
                Text('· tag: ${r.tag}', style: MonitorText.muted),
              if (r.retryCount > 0)
                Text('· retry ${r.retryCount}', style: MonitorText.muted),
              if (r.previousAttemptId != null)
                InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CallDetailScreen(
                        recordId: r.previousAttemptId!,
                      ),
                    ),
                  ),
                  child: Text(
                    '· retry of previous attempt ↗',
                    style: MonitorText.muted.copyWith(
                      color: MonitorPalette.accent,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _statusLabel(ApiCallRecord r) {
    if (r.cancelled) return 'CANCELLED';
    if (r.errorKind != null && r.responseStatus == null) {
      return r.errorKind!.label.toUpperCase();
    }
    if (r.responseStatus != null) return '${r.responseStatus}';
    return r.completedAt == null ? 'IN-FLIGHT' : 'UNKNOWN';
  }
}

class _SizeBadge extends StatelessWidget {
  const _SizeBadge({
    required this.label,
    required this.size,
    required this.color,
  });

  final String label;
  final int size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                color: color,
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(width: 6),
          Text(
            size > 0 ? formatBytes(size) : '—',
            style: const TextStyle(
              color: MonitorPalette.textPrimary,
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthTokenPanel extends StatefulWidget {
  const _AuthTokenPanel({required this.token});

  final String token;

  @override
  State<_AuthTokenPanel> createState() => _AuthTokenPanelState();
}

class _AuthTokenPanelState extends State<_AuthTokenPanel> {
  bool _revealed = false;

  String _bareToken() {
    final t = widget.token.trim();
    if (t.toLowerCase().startsWith('bearer ')) {
      return t.substring(7).trim();
    }
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final bare = _bareToken();
    final preview = _revealed
        ? widget.token
        : (bare.length > 8
            ? '${widget.token.substring(0, widget.token.length - bare.length)}'
                '${bare.substring(0, 4)}…${bare.substring(bare.length - 4)}'
            : '••••••••');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Auth token', style: MonitorText.heading),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: MonitorPalette.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'SENSITIVE',
                style: TextStyle(
                  color: MonitorPalette.warning,
                  fontSize: 9,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: _revealed ? 'Hide' : 'Reveal',
              icon: Icon(
                _revealed ? Icons.visibility_off : Icons.visibility,
                size: 18,
                color: MonitorPalette.textSecondary,
              ),
              onPressed: () => setState(() => _revealed = !_revealed),
            ),
            IconButton(
              tooltip: 'Copy full token',
              icon: const Icon(Icons.copy,
                  size: 18, color: MonitorPalette.textSecondary),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.token));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Auth token copied')),
                );
              },
            ),
            IconButton(
              tooltip: 'Copy raw token (no Bearer)',
              icon: const Icon(Icons.content_paste_go_outlined,
                  size: 18, color: MonitorPalette.textSecondary),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: bare));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bare token copied')),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: MonitorPalette.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: MonitorPalette.border),
          ),
          child: SelectableText(preview, style: MonitorText.mono),
        ),
      ],
    );
  }
}
