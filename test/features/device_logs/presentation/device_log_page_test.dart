import 'dart:async';
import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:aipin/features/device_logs/data/file_app_log_store.dart';
import 'package:aipin/features/device_logs/domain/app_log_entry.dart';
import 'package:aipin/features/device_logs/domain/app_log_upload_port.dart';
import 'package:aipin/features/device_logs/domain/public_diagnostic_log_sink.dart';
import 'package:aipin/features/device_logs/presentation/device_log_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('resuming shows entries received while the view was paused', (
    tester,
  ) async {
    final store = _StubLogStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(home: DeviceLogPage(store: store)));
    await tester.tap(find.byTooltip('暂停跟随'));
    store.emit('received_while_paused');
    await tester.pump();
    expect(find.textContaining('received_while_paused'), findsNothing);
    await tester.tap(find.byTooltip('继续跟随'));
    await tester.pump();
    expect(find.textContaining('received_while_paused'), findsOneWidget);
  });
  testWidgets('shows live entries, path and view controls', (tester) async {
    final store = _StubLogStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(home: DeviceLogPage(store: store)));

    expect(find.text('实时日志'), findsOneWidget);
    expect(find.byTooltip('暂停跟随'), findsOneWidget);
    expect(find.byTooltip('导出日志'), findsOneWidget);
    expect(find.byTooltip('上传日志'), findsOneWidget);
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

  testWidgets('upload action confirms and blocks duplicate taps while active', (
    tester,
  ) async {
    final store = _StubLogStore();
    final upload = Completer<AppLogUploadReceipt>();
    var uploads = 0;
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceLogPage(
          store: store,
          onUpload: () {
            uploads += 1;
            return upload.future;
          },
        ),
      ),
    );

    await tester.tap(find.byTooltip('上传日志'));
    await tester.pumpAndSettle();
    expect(find.text('上传运行日志'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, '确认上传'));
    await tester.pump();

    expect(uploads, 1);
    expect(find.byTooltip('正在上传'), findsOneWidget);

    upload.complete(const AppLogUploadReceipt(bytes: 2048));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('日志已上报（2.0 KB）'), findsOneWidget);
  });

  testWidgets(
    'disposing the store cancels its pending write debounce during teardown',
    (tester) async {
      final store = FileAppLogStore(
        enabled: true,
        supportDirectoryProvider: () async {
          throw StateError('Storage is intentionally unavailable in this test');
        },
      );
      addTearDown(store.dispose);

      await tester.pumpWidget(MaterialApp(home: DeviceLogPage(store: store)));
      store.info('queued_before_widget_teardown', scope: 'BLE');

      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      await tester.pump();
    },
  );
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
