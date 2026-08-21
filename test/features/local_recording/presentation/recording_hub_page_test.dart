import 'package:evt_ble_app/features/local_recording/presentation/recording_hub_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'hub leaves local recording enabled offline and explains unavailable hardware',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: RecordingHubPage(isHardwareObservable: false)),
      );

      expect(find.text('本机录音'), findsOneWidget);
      expect(find.byTooltip('开始本机录音'), findsOneWidget);
      expect(find.text('连接设备后观察录音状态'), findsOneWidget);
    },
  );
}
