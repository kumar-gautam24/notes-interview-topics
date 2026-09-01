import '../core/monitor_config.dart';
import '../model/endpoint_rule.dart';

/// Two responsibilities:
/// 1. Reduce a concrete URL path to a template suitable for grouping
///    (e.g. `/profile/123` → `/profile/{id}`).
/// 2. Match a path against an [EndpointRule.pattern] glob.
class EndpointMatcher {
  const EndpointMatcher();

  /// Convert a path into a stable template by replacing numeric and
  /// uuid-looking segments with `{id}`. Idempotent.
  String templateFor(String path) {
    final trimmed = _stripQuery(path);
    final segments = trimmed.split('/');
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      if (s.isEmpty) continue;
      if (_looksLikeId(s)) {
        segments[i] = '{id}';
      }
    }
    return segments.join('/');
  }

  static bool _looksLikeId(String s) {
    if (RegExp(r'^\d+$').hasMatch(s)) {
      return true;
    }
    if (RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(s)) {
      return true;
    }
    if (s.length >= 16 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(s)) {
      return true;
    }
    return false;
  }

  static String _stripQuery(String url) {
    final qIdx = url.indexOf('?');
    if (qIdx < 0) return url;
    return url.substring(0, qIdx);
  }

  /// Find the first rule whose [EndpointRule.pattern] matches [path].
  EndpointRule? findRule(String path, MonitorConfig config) {
    if (config.endpointRules.isEmpty) return null;
    final stripped = _stripQuery(path);
    for (final rule in config.endpointRules.values) {
      if (_matchesGlob(stripped, rule.pattern)) return rule;
    }
    return null;
  }

  /// Glob matcher: `*` = anything except `/`, `**` = anything.
  static bool _matchesGlob(String input, String pattern) {
    final regex = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final c = pattern[i];
      if (c == '*') {
        if (i + 1 < pattern.length && pattern[i + 1] == '*') {
          regex.write('.*');
          i++;
        } else {
          regex.write('[^/]*');
        }
      } else if ('.+?()|[]{}^\$\\'.contains(c)) {
        regex
          ..write('\\')
          ..write(c);
      } else {
        regex.write(c);
      }
    }
    regex.write(r'$');
    try {
      return RegExp(regex.toString()).hasMatch(input);
    } catch (_) {
      return false;
    }
  }
}
