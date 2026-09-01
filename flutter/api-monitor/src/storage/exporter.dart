import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../model/api_call_record.dart';

/// Writes captured records to a temporary file and hands it to the native
/// share sheet. Two formats:
///
///   * **JSON** — exact toJson() of every record, in an array. Round-trips
///     back through `ApiCallRecord.fromJson`.
///   * **HAR**  — HTTP Archive 1.2 (subset). Importable into Charles,
///     Postman, Chrome DevTools, and most JSON-aware tools.
class Exporter {
  const Exporter();

  Future<void> shareJson({
    required Iterable<ApiCallRecord> records,
    String filenameHint = 'api-monitor',
  }) async {
    final list = records.toList();
    final encoded = const JsonEncoder.withIndent('  ')
        .convert(list.map((r) => r.toJson()).toList());
    final file = await _writeTemp(
      filename: '${filenameHint}_${_stamp()}.json',
      contents: encoded,
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        text: 'API Monitor export — ${list.length} record(s)',
      ),
    );
  }

  Future<void> shareHar({
    required Iterable<ApiCallRecord> records,
    String filenameHint = 'api-monitor',
  }) async {
    final list = records.toList();
    final har = _buildHar(list);
    final encoded = const JsonEncoder.withIndent('  ').convert(har);
    final file = await _writeTemp(
      filename: '${filenameHint}_${_stamp()}.har',
      contents: encoded,
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        text: 'API Monitor HAR export — ${list.length} entries',
      ),
    );
  }

  Future<File> _writeTemp({
    required String filename,
    required String contents,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(contents, flush: true);
    return file;
  }

  String _stamp() {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  // ───────── HAR builder ─────────

  Map<String, dynamic> _buildHar(List<ApiCallRecord> records) {
    return {
      'log': {
        'version': '1.2',
        'creator': {
          'name': '<AppName> API Monitor',
          'version': '1.0',
        },
        'entries': records.map(_harEntry).toList(),
      },
    };
  }

  Map<String, dynamic> _harEntry(ApiCallRecord r) {
    final reqHeaders = (r.requestHeaders ?? const {})
        .entries
        .map((e) => {'name': e.key, 'value': e.value})
        .toList();
    final resHeaders = (r.responseHeaders ?? const {})
        .entries
        .map((e) => {'name': e.key, 'value': e.value})
        .toList();

    Uri uri;
    try {
      uri = Uri.parse(r.url);
    } catch (_) {
      uri = Uri();
    }
    final queryString = uri.queryParameters.entries
        .map((e) => {'name': e.key, 'value': e.value})
        .toList();

    return {
      'startedDateTime': r.startedAt.toUtc().toIso8601String(),
      'time': r.timing?.totalMs ?? 0,
      'request': {
        'method': r.method,
        'url': r.url,
        'httpVersion': 'HTTP/1.1',
        'headers': reqHeaders,
        'queryString': queryString,
        'cookies': const [],
        'headersSize': -1,
        'bodySize': r.requestBodySize,
        if (r.requestBody != null && r.requestBody!.isNotEmpty)
          'postData': {
            'mimeType': _guessMime(r.requestHeaders) ?? 'text/plain',
            'text': r.requestBody,
          },
      },
      'response': {
        'status': r.responseStatus ?? 0,
        'statusText': _statusText(r),
        'httpVersion': 'HTTP/1.1',
        'headers': resHeaders,
        'cookies': const [],
        'content': {
          'size': r.responseBodySize,
          'mimeType': _guessMime(r.responseHeaders) ?? 'text/plain',
          if (r.responseBody != null) 'text': r.responseBody,
        },
        'redirectURL': '',
        'headersSize': -1,
        'bodySize': r.responseBodySize,
      },
      'cache': const {},
      'timings': {
        'send': 0,
        'wait': r.timing?.waitMs ?? -1,
        'receive': r.timing?.downloadMs ?? -1,
      },
      '_apiMonitor': {
        'id': r.id,
        'endpointTemplate': r.endpointTemplate,
        if (r.errorKind != null) 'errorKind': r.errorKind!.name,
        if (r.errorMessage != null) 'errorMessage': r.errorMessage,
        if (r.cancelled) 'cancelled': true,
        if (r.tag != null) 'tag': r.tag,
        if (r.retryCount > 0) 'retryCount': r.retryCount,
      },
    };
  }

  String? _guessMime(Map<String, String>? headers) {
    if (headers == null) return null;
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == 'content-type') {
        final raw = e.value;
        final semi = raw.indexOf(';');
        return semi == -1 ? raw : raw.substring(0, semi);
      }
    }
    return null;
  }

  String _statusText(ApiCallRecord r) {
    if (r.cancelled) return 'Cancelled';
    if (r.errorKind != null && r.responseStatus == null) {
      return r.errorKind!.label;
    }
    return '';
  }
}
