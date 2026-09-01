import 'package:flutter/material.dart';

import '../model/enums.dart';

/// Self-contained color/style helpers. The package intentionally does not
/// depend on the host app's theme — it must drop into other projects with
/// no edits.
class MonitorPalette {
  static const bgDark = Color(0xFF0F1115);
  static const surface = Color(0xFF181B22);
  static const surfaceAlt = Color(0xFF22262F);
  static const border = Color(0xFF2A2F3A);
  static const textPrimary = Color(0xFFE7E9EE);
  static const textSecondary = Color(0xFF9AA1AE);
  static const accent = Color(0xFF4F8DFD);

  static const success = Color(0xFF34C759);
  static const warning = Color(0xFFFFC542);
  static const danger = Color(0xFFFF453A);
  static const muted = Color(0xFF8E8E93);

  static Color forStatus(CallStatus s) {
    return switch (s) {
      CallStatus.success => success,
      CallStatus.clientError => warning,
      CallStatus.serverError => danger,
      CallStatus.networkError => danger,
      CallStatus.timeout => danger,
      CallStatus.cancelled => muted,
      CallStatus.inFlight => accent,
      CallStatus.unknown => muted,
    };
  }

  static Color forMethod(String method) {
    return switch (method.toUpperCase()) {
      'GET' => const Color(0xFF61AFFE),
      'POST' => const Color(0xFF49CC90),
      'PUT' => const Color(0xFFFCA130),
      'PATCH' => const Color(0xFF50E3C2),
      'DELETE' => const Color(0xFFF93E3E),
      _ => muted,
    };
  }
}

class MonitorText {
  static const heading = TextStyle(
    color: MonitorPalette.textPrimary,
    fontWeight: FontWeight.w600,
    fontSize: 16,
  );
  static const body = TextStyle(
    color: MonitorPalette.textPrimary,
    fontSize: 13,
  );
  static const muted = TextStyle(
    color: MonitorPalette.textSecondary,
    fontSize: 12,
  );
  static const mono = TextStyle(
    color: MonitorPalette.textPrimary,
    fontSize: 12,
    fontFamily: 'monospace',
    height: 1.35,
  );
  static const monoMuted = TextStyle(
    color: MonitorPalette.textSecondary,
    fontSize: 11,
    fontFamily: 'monospace',
  );
  static const monoSmall = TextStyle(
    color: MonitorPalette.textPrimary,
    fontSize: 11,
    fontFamily: 'monospace',
  );
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)}MB';
}

String formatLatency(int? ms) {
  if (ms == null) return '—';
  if (ms < 1000) return '${ms}ms';
  return '${(ms / 1000).toStringAsFixed(2)}s';
}

String formatTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  String three(int n) => n.toString().padLeft(3, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)}';
}

String formatRelative(DateTime? t) {
  if (t == null) return '—';
  final delta = DateTime.now().difference(t);
  if (delta.inSeconds < 60) return '${delta.inSeconds}s ago';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
  if (delta.inHours < 24) return '${delta.inHours}h ago';
  return '${delta.inDays}d ago';
}
