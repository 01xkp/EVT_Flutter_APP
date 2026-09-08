import 'dart:async';
import 'package:aipin/features/device_logs/data/file_app_log_store.dart';
import 'package:aipin/features/device_logs/domain/app_log_entry.dart';
import 'package:aipin/features/device_logs/domain/public_diagnostic_log_sink.dart';
import 'package:aipin/features/device_logs/presentation/device_log_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows live entries, path and view controls', (tester) async {
    final store = _StubLogStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(home: DeviceLogPage(store: store)));

    expect(find.text('实时日志'), findsOneWidget);
    expect(find.byTooltip('暂停跟随'), findsOneWidget);
    expect(find.byTooltip('导出日志'), findsOneWidget);
    store.emit('live_event');
    await tester.pump();
    expect(find.textContaining('live_event'), findsOneWidget);
  });

  testWidgets('shows the public mirror location when it is available', (
    tester,
  ) async {
    final store = _StubLogStore(
      mirror: PublicDiagnosticLogMirrorStatus.success(
        relativePath: 'Download/AIPIN/logs/aipin-2026-09-08.log',
        lastUpdatedAt: DateTime.utc(2026, 9, 8),
      ),
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(home: DeviceLogPage(store: store)));

    expect(
      find.textContaining('已保存到：Download/AIPIN/logs/aipin-'),
      findsOneWidget,
    );
  });

  testWidgets('export action forwards the flushed canonical path', (
    tester,
  ) async {
    final store = _StubLogStore(
      exportPathValue: '/app/logs/aipin-2026-09-08.log',
    );
    final exported = Completer<String>();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceLogPage(
          store: store,
          onExport: (path) async => exported.complete(path),
        ),
      ),
    );

    await tester.tap(find.byTooltip('导出日志'));
    await tester.pump();
    final path = await exported.future.timeout(const Duration(seconds: 2));

    expect(path, '/app/logs/aipin-2026-09-08.log');
  });
}

class _StubLogStore extends FileAppLogStore {
  _StubLogStore({this.mirror, this.exportPathValue}) : super(enabled: false);

  final PublicDiagnosticLogMirrorStatus? mirror;
  final String? exportPathValue;
  final List<AppLogEntry> _liveEntries = <AppLogEntry>[];

  @override
  List<AppLogEntry> get entries => List.unmodifiable(_liveEntries);

  void emit(String event) {
    _liveEntries.add(
      AppLogEntry(
        timestamp: DateTime.utc(2026, 9, 8),
        scope: 'APP',
        event: event,
      ),
    );
    notifyListeners();
  }

  @override
  PublicDiagnosticLogMirrorStatus? get publicMirrorStatus => mirror;

  @override
  Future<String?> exportPath() async => exportPathValue;
}
