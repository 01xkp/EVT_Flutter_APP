import 'package:aipin/features/home/presentation/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'home keeps local recording available while device is disconnected',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            device: const DeviceSummary.disconnected(name: 'AIPIN-01'),
            onConnectDevice: () {},
            onStartLocalRecording: () {},
            onOpenSettings: () {},
          ),
        ),
      );

      expect(find.text('尚未连接'), findsOneWidget);
      expect(find.text('连接设备'), findsOneWidget);
      expect(find.text('本机录音'), findsOneWidget);
      expect(find.text('无需连接设备'), findsOneWidget);
    },
  );

  testWidgets('shows a recoverable status while reconnecting or exhausted', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          device: const DeviceSummary.reconnecting(name: 'AIPIN-01'),
          onConnectDevice: () {},
          onStartLocalRecording: () {},
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
          onStartLocalRecording: () {},
          onOpenSettings: () {},
        ),
      ),
    );

    expect(find.text('回连失败，可再次尝试'), findsOneWidget);
    expect(find.text('重新连接'), findsOneWidget);
  });
}
