import 'dart:convert';

import '../core/monitor_config.dart';

/// Stateless redaction pipeline. All methods return new values; never mutate
/// the inputs. Used by the interceptor before storing a record.
class Redactor {
  const Redactor(this.config);

  final RedactionConfig config;

  static const _mask = '***';

  /// Mask sensitive headers in-place semantics: returns a new map with
  /// denied keys replaced by [_mask] (or, for `Authorization`, a partial
  /// preview of the token's tail so devs can correlate without exposing it).
  Map<String, String> redactHeaders(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return const {};
    final denyset = config.headerDenylist
        .map((s) => s.toLowerCase())
        .toSet();
    final out = <String, String>{};
    headers.forEach((k, v) {
      final lower = k.toLowerCase();
      if (denyset.contains(lower)) {
        out[k] = _maskHeaderValue(lower, v);
      } else {
        out[k] = v;
      }
    });
    return out;
  }

  String _maskHeaderValue(String lowerKey, String value) {
    if (lowerKey == 'authorization') {
      // Keep "Bearer " prefix and last 4 chars: "Bearer ****…ab12"
      final trimmed = value.trim();
      if (trimmed.toLowerCase().startsWith('bearer ') && trimmed.length > 11) {
        final tail = trimmed.substring(trimmed.length - 4);
        return 'Bearer ****…$tail';
      }
    }
    return _mask;
  }

  /// Redact denylisted query parameters from a URL string. Returns the URL
  /// unchanged if it can't be parsed.
  String redactUrl(String url) {
    Uri parsed;
    try {
      parsed = Uri.parse(url);
    } catch (_) {
      return url;
    }
    if (parsed.queryParameters.isEmpty) return url;
    final denyset = config.urlQueryDenylist
        .map((s) => s.toLowerCase())
        .toSet();
    if (parsed.queryParameters.keys
        .every((k) => !denyset.contains(k.toLowerCase()))) {
      return url;
    }
    final newQuery = <String, String>{};
    parsed.queryParameters.forEach((k, v) {
      newQuery[k] = denyset.contains(k.toLowerCase()) ? _mask : v;
    });
    return parsed.replace(queryParameters: newQuery).toString();
  }

  /// Redact denylisted JSON keys recursively. If [bodyText] is not valid JSON
  /// the original string is returned unchanged. The match is case-insensitive
  /// on key names.
  String? redactBody(String? bodyText) {
    if (bodyText == null || bodyText.isEmpty) return bodyText;
    final denyset =
        config.bodyJsonKeys.map((s) => s.toLowerCase()).toSet();
    dynamic decoded;
    try {
      decoded = jsonDecode(bodyText);
    } catch (_) {
      return bodyText;
    }
    final cleaned = _walk(decoded, denyset);
    try {
      return jsonEncode(cleaned);
    } catch (_) {
      return bodyText;
    }
  }

  dynamic _walk(dynamic node, Set<String> denyset) {
    if (node is Map) {
      final out = <String, dynamic>{};
      node.forEach((k, v) {
        final keyStr = k.toString();
        if (denyset.contains(keyStr.toLowerCase())) {
          out[keyStr] = _mask;
        } else {
          out[keyStr] = _walk(v, denyset);
        }
      });
      return out;
    }
    if (node is List) {
      return node.map((e) => _walk(e, denyset)).toList();
    }
    return node;
  }

  /// Cap a body to [maxBytes] (UTF-8). Appends a marker if truncated.
  static String? cap(String? body, int maxBytes) {
    if (body == null) return null;
    final bytes = utf8.encode(body);
    if (bytes.length <= maxBytes) return body;
    final head = utf8.decode(bytes.sublist(0, maxBytes), allowMalformed: true);
    return '$head\n…[truncated ${bytes.length - maxBytes} bytes]';
  }
}
