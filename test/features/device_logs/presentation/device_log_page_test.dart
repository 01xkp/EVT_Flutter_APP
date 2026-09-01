import 'dart:io';

import 'package:aipin/features/device_logs/data/file_app_log_store.dart';
import 'package:aipin/features/device_logs/presentation/device_log_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows live entries, path and view controls', (tester) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('aipin-log-widget-'),
    ))!;
    addTearDown(() => root.delete(recursive: true));
    final store = FileAppLogStore(
      supportDirectoryProvider: () async => root,
      enabled: true,
    );
    await tester.runAsync(store.initialize);
    await tester.pumpWidget(MaterialApp(home: DeviceLogPage(store: store)));

    expect(find.text('实时日志'), findsOneWidget);
    expect(find.byTooltip('暂停跟随'), findsOneWidget);
    expect(find.byTooltip('导出日志'), findsOneWidget);
    await tester.runAsync(() async {
      store.info('live_event');
      await store.flush();
    });
    await tester.pump();
    expect(find.textContaining('live_event'), findsOneWidget);
    await tester.runAsync(store.close);
    store.dispose();
  });
}
