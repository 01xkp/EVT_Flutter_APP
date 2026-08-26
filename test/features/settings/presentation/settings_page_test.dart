import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings identifies an incomplete GATT profile', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(profile: DeviceProfile.empty())),
    );

    expect(find.text('GATT 配置未完成'), findsOneWidget);
    expect(find.text('扫描规则可用，连接验证已阻止'), findsOneWidget);
  });
}
