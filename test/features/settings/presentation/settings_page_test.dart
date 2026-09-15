import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/core/permissions/app_permission_gateway.dart';
import 'package:aipin/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('refreshes permission after returning from system settings', (
    tester,
  ) async {
    final permissions = _MutablePermissions();
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          profile: DeviceProfile.empty(),
          permissions: permissions,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('需要开启'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    permissions.state = AppPermissionState.granted;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('已开启'), findsOneWidget);
    expect(find.text('需要开启'), findsNothing);
  });

  testWidgets('settings identifies an incomplete GATT profile', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(profile: DeviceProfile.empty())),
    );

    expect(find.text('GATT 配置未完成'), findsOneWidget);
    expect(find.text('扫描规则可用，连接验证已阻止'), findsOneWidget);
  });
}

class _MutablePermissions implements AppPermissionGateway {
  AppPermissionState state = AppPermissionState.denied;
  @override
  Future<AppPermissionState> nearbyDevices() async => state;
  @override
  Future<bool> openSettings() async => true;
}
