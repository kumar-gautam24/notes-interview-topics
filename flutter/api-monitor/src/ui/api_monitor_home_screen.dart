import 'package:flutter/material.dart';

import '../core/api_monitor.dart';
import '../core/monitor_config.dart';
import '_palette.dart';
import 'endpoints_tab.dart';
import 'settings_tab.dart';
import 'timeline_tab.dart';

class ApiMonitorHomeScreen extends StatelessWidget {
  const ApiMonitorHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!ApiMonitor.instance.isInitialized) {
      return const _NotInitializedScaffold();
    }
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: MonitorPalette.bgDark,
        appBarTheme: const AppBarTheme(
          backgroundColor: MonitorPalette.bgDark,
          foregroundColor: MonitorPalette.textPrimary,
          elevation: 0,
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: MonitorPalette.accent,
          unselectedLabelColor: MonitorPalette.textSecondary,
          indicatorColor: MonitorPalette.accent,
          labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        dividerColor: MonitorPalette.border,
      ),
      child: DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('API Monitor'),
            actions: [
              StreamBuilder<MonitorConfig>(
                stream: ApiMonitor.instance.configStore.changes,
                initialData: ApiMonitor.instance.configStore.current,
                builder: (context, snap) {
                  final cfg = snap.data ?? const MonitorConfig();
                  final enabled = cfg.enabled;
                  final paused = cfg.paused;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: paused ? 'Resume capture' : 'Pause capture',
                          icon: Icon(
                            paused
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                            color: paused
                                ? MonitorPalette.warning
                                : MonitorPalette.textSecondary,
                          ),
                          onPressed: enabled
                              ? () => ApiMonitor.instance
                                  .updateConfig(cfg.copyWith(paused: !paused))
                              : null,
                        ),
                        Text(
                          paused
                              ? 'PAUSED'
                              : (enabled ? 'ON' : 'OFF'),
                          style: TextStyle(
                            color: paused
                                ? MonitorPalette.warning
                                : (enabled
                                    ? MonitorPalette.success
                                    : MonitorPalette.muted),
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Switch.adaptive(
                          value: enabled,
                          activeThumbColor: MonitorPalette.success,
                          onChanged: (v) => ApiMonitor.instance.updateConfig(
                            cfg.copyWith(enabled: v),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                color: MonitorPalette.surface,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'export_json',
                    child: Row(children: [
                      Icon(Icons.ios_share, size: 16,
                          color: MonitorPalette.textPrimary),
                      SizedBox(width: 8),
                      Text('Share all as JSON',
                          style: TextStyle(color: MonitorPalette.textPrimary)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'export_har',
                    child: Row(children: [
                      Icon(Icons.archive_outlined, size: 16,
                          color: MonitorPalette.textPrimary),
                      SizedBox(width: 8),
                      Text('Share all as HAR',
                          style: TextStyle(color: MonitorPalette.textPrimary)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'clear',
                    child: Row(children: [
                      Icon(Icons.delete_outline, size: 16,
                          color: MonitorPalette.danger),
                      SizedBox(width: 8),
                      Text('Clear all logs',
                          style: TextStyle(color: MonitorPalette.danger)),
                    ]),
                  ),
                ],
                onSelected: (v) async {
                  final messenger = ScaffoldMessenger.of(context);
                  final all = ApiMonitor.instance.store.all();
                  switch (v) {
                    case 'export_json':
                      if (all.isEmpty) {
                        _showToast(messenger, 'Nothing to export');
                        return;
                      }
                      try {
                        await ApiMonitor.instance.exporter
                            .shareJson(records: all);
                      } catch (e) {
                        _showToast(messenger, 'Export failed: $e');
                      }
                      break;
                    case 'export_har':
                      if (all.isEmpty) {
                        _showToast(messenger, 'Nothing to export');
                        return;
                      }
                      try {
                        await ApiMonitor.instance.exporter
                            .shareHar(records: all);
                      } catch (e) {
                        _showToast(messenger, 'Export failed: $e');
                      }
                      break;
                    case 'clear':
                      await ApiMonitor.instance.clearLogs();
                      break;
                  }
                },
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Timeline'),
                Tab(text: 'Endpoints'),
                Tab(text: 'Errors'),
                Tab(text: 'Settings'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              TimelineTab(),
              EndpointsTab(),
              TimelineTab(lockErrorsOnly: true),
              SettingsTab(),
            ],
          ),
        ),
      ),
    );
  }

  static void _showToast(ScaffoldMessengerState messenger, String text) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _NotInitializedScaffold extends StatelessWidget {
  const _NotInitializedScaffold();

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: MonitorPalette.bgDark,
        appBarTheme: const AppBarTheme(
          backgroundColor: MonitorPalette.bgDark,
          foregroundColor: MonitorPalette.textPrimary,
        ),
      ),
      child: Scaffold(
        appBar: AppBar(title: const Text('API Monitor')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'API Monitor is not initialized.\n\n'
              'Call `await ApiMonitor.instance.init()` during app startup '
              '(inside a kDebugMode guard).',
              style: MonitorText.muted,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
