import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';

import 'monitor_config.dart';

/// Persists [MonitorConfig] as a JSON string in a small Hive box. Avoids
/// `hive_generator` codegen entirely.
class ConfigStore {
  ConfigStore({this.boxName = 'api_monitor_config'});

  final String boxName;

  static const _key = 'config';

  Box<dynamic>? _box;
  MonitorConfig _current = const MonitorConfig();
  final _controller = StreamController<MonitorConfig>.broadcast();

  MonitorConfig get current => _current;

  /// Fires whenever [save] writes a new config.
  Stream<MonitorConfig> get changes => _controller.stream;

  Future<void> init() async {
    _box = await Hive.openBox<dynamic>(boxName);
    final raw = _box!.get(_key);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _current = MonitorConfig.fromJson(decoded);
        }
      } catch (_) {
        // Corrupt config — fall back to defaults and overwrite on next save.
      }
    } else {
      // First launch: persist defaults so users see the starting state.
      await save(_current);
    }
  }

  Future<void> save(MonitorConfig config) async {
    _current = config;
    final box = _box;
    if (box != null) {
      await box.put(_key, jsonEncode(config.toJson()));
    }
    _controller.add(config);
  }

  Future<void> close() async {
    await _controller.close();
    await _box?.close();
  }
}
