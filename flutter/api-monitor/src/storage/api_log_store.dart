import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';

import '../model/api_call_record.dart';

/// Coalesces a burst of upstream events into a single trailing emit.
/// Used to keep the UI from rebuilding once per Dio event when many
/// requests fire in quick succession (a typical screen load fires
/// 10–20 events in under a second).
Stream<T> _debounce<T>(Stream<T> source, Duration duration) {
  final controller = StreamController<T>.broadcast(sync: false);
  Timer? timer;
  T? lastValue;
  bool hasPending = false;

  final subscription = source.listen(
    (value) {
      lastValue = value;
      hasPending = true;
      timer?.cancel();
      timer = Timer(duration, () {
        if (hasPending) {
          hasPending = false;
          controller.add(lastValue as T);
        }
      });
    },
    onError: controller.addError,
    onDone: () {
      timer?.cancel();
      if (hasPending) controller.add(lastValue as T);
      controller.close();
    },
  );

  controller.onCancel = () async {
    timer?.cancel();
    await subscription.cancel();
  };
  return controller.stream;
}

/// Hive-backed bounded ring store. One entry per call, keyed by the call's
/// monotonically-increasing internal id. Eviction is FIFO by Hive insertion
/// order; we keep a separate `_indexBox` so we can prune the oldest without
/// scanning every record.
///
/// All public mutations notify [changes] so the UI can rebuild.
class ApiLogStore {
  ApiLogStore({this.boxName = 'api_monitor_logs', this.indexBoxName = 'api_monitor_logs_idx'});

  final String boxName;
  final String indexBoxName;

  Box<dynamic>? _box;
  Box<dynamic>? _indexBox;
  final _controller = StreamController<void>.broadcast();
  int _maxRecords = 1000;
  Duration _ttl = const Duration(days: 7);

  Stream<void> get changes => _controller.stream;

  /// Debounced variant of [changes] — coalesces bursts of upserts into
  /// a single trailing emit ~80 ms after the last write. UI consumers
  /// (Timeline, Endpoints) should prefer this to avoid rebuilding once
  /// per intercepted Dio event.
  late final Stream<void> changesDebounced =
      _debounce(_controller.stream, const Duration(milliseconds: 80));

  Future<void> init({required int maxRecords, required int ttlDays}) async {
    _maxRecords = maxRecords;
    _ttl = Duration(days: ttlDays);
    _box = await Hive.openBox<dynamic>(boxName);
    _indexBox = await Hive.openBox<dynamic>(indexBoxName);
    await _purgeExpired();
  }

  void updateRetention({required int maxRecords, required int ttlDays}) {
    _maxRecords = maxRecords;
    _ttl = Duration(days: ttlDays);
  }

  Future<void> upsert(ApiCallRecord record) async {
    final box = _box;
    final indexBox = _indexBox;
    if (box == null || indexBox == null) return;
    final encoded = jsonEncode(record.toJson());
    await box.put(record.id, encoded);
    // Track insertion order: only add the id once.
    if (!indexBox.containsKey(record.id)) {
      await indexBox.put(record.id, record.startedAt.toIso8601String());
      await _enforceCap();
    }
    _controller.add(null);
  }

  Future<void> _enforceCap() async {
    final indexBox = _indexBox;
    final box = _box;
    if (indexBox == null || box == null) return;
    while (indexBox.length > _maxRecords) {
      final oldestKey = indexBox.keyAt(0);
      await indexBox.delete(oldestKey);
      await box.delete(oldestKey);
    }
  }

  Future<void> _purgeExpired() async {
    final indexBox = _indexBox;
    final box = _box;
    if (indexBox == null || box == null) return;
    final cutoff = DateTime.now().subtract(_ttl);
    final toDelete = <dynamic>[];
    for (final key in indexBox.keys) {
      final ts = indexBox.get(key);
      if (ts is String) {
        final parsed = DateTime.tryParse(ts);
        if (parsed != null && parsed.isBefore(cutoff)) {
          toDelete.add(key);
        }
      }
    }
    if (toDelete.isNotEmpty) {
      await indexBox.deleteAll(toDelete);
      await box.deleteAll(toDelete);
    }
  }

  /// All records, newest first.
  List<ApiCallRecord> all() {
    final box = _box;
    if (box == null) return const [];
    final out = <ApiCallRecord>[];
    for (final raw in box.values) {
      final record = _decode(raw);
      if (record != null) out.add(record);
    }
    out.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return out;
  }

  ApiCallRecord? get(String id) {
    final raw = _box?.get(id);
    return _decode(raw);
  }

  ApiCallRecord? _decode(dynamic raw) {
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return ApiCallRecord.fromJson(decoded);
    } catch (_) {}
    return null;
  }

  Future<void> delete(String id) async {
    await _box?.delete(id);
    await _indexBox?.delete(id);
    _controller.add(null);
  }

  Future<void> clear() async {
    await _box?.clear();
    await _indexBox?.clear();
    _controller.add(null);
  }

  Future<void> close() async {
    await _controller.close();
    await _box?.close();
    await _indexBox?.close();
  }
}
