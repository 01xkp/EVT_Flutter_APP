import 'package:aipin/features/local_recording/presentation/recording_hub_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('recording destination exposes one local recording action', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: RecordingHubPage(isHardwareObservable: false)),
    );

    expect(find.text('开始本机录音'), findsOneWidget);
    expect(find.text('AI 语音'), findsNothing);
    expect(find.text('无需连接设备'), findsOneWidget);
    expect(find.text('设备录音状态'), findsOneWidget);
    expect(find.text('开始设备录音'), findsNothing);
  });
}
