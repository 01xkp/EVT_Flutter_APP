import 'package:aipin/features/home/presentation/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home provides files, saved recordings and logs directly', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          device: const DeviceSummary.disconnected(name: '测试设备'),
          onConnectDevice: () {},
          onOpenSettings: () {},
          onOpenFiles: () => opened.add('device'),
          onOpenSavedRecordings: () => opened.add('local'),
          onOpenLogs: () => opened.add('logs'),
        ),
      ),
    );
    for (final label in ['设备录音文件', '已保存录音', '实时日志']) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
    }
    expect(opened, ['device', 'local', 'logs']);
  });
  testWidgets('settings is reachable by a visible Chinese action', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          device: const DeviceSummary.disconnected(name: '测试设备'),
          onConnectDevice: () {},
          onOpenSettings: () => opened = true,
        ),
      ),
    );
    await tester.tap(find.text('设置'));
    expect(opened, isTrue);
  });
  testWidgets('home exposes device status while device is disconnected', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          device: const DeviceSummary.disconnected(name: 'AIPIN-01'),
          onConnectDevice: () {},
          onOpenSettings: () {},
        ),
      ),
    );

    expect(find.text('尚未连接'), findsOneWidget);
    expect(find.text('连接设备'), findsOneWidget);
    expect(find.text('设备状态'), findsOneWidget);
    expect(find.text('本机录音'), findsNothing);
  });

  testWidgets('shows a recoverable status while reconnecting or exhausted', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          device: const DeviceSummary.reconnecting(name: 'AIPIN-01'),
          onConnectDevice: () {},
          onOpenSettings: () {},
        ),
      ),
    );

    expect(find.text('正在回连设备'), findsOneWidget);
    expect(find.text('正在回连'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          device: const DeviceSummary.reconnectFailed(name: 'AIPIN-01'),
          onConnectDevice: () {},
          onOpenSettings: () {},
        ),
      ),
    );

    expect(find.text('回连失败，可再次尝试'), findsOneWidget);
    expect(find.text('重新连接'), findsOneWidget);
  });
}
