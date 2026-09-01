import 'dart:typed_data';

import 'package:aipin/features/device_session/application/wqota_update_controller.dart';
import 'package:aipin/features/device_session/domain/firmware_package.dart';
import 'package:aipin/features/device_session/domain/firmware_package_gateway.dart';
import 'package:aipin/features/device_session/presentation/firmware_update_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows an actionable blocked state without a firmware service', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FirmwareUpdatePage(
          deviceId: 'device-1',
          deviceName: 'AIPIN_8423',
          loadPackage: () => Future<FirmwarePackage>.error(
            const FirmwarePackageUnavailableException(),
          ),
          createUpdateController: _unusedController,
          reconnectAndVerify: _unusedReconnect,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('暂时无法获取固件'), findsOneWidget);
    expect(find.text('重新检查'), findsOneWidget);
    expect(find.textContaining('固件包服务未配置'), findsWidgets);
  });

  testWidgets('shows the explicit post-update business version before start', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FirmwareUpdatePage(
          deviceId: 'device-1',
          deviceName: 'AIPIN_8423',
          loadPackage: () async => _package(),
          createUpdateController: _unusedController,
          reconnectAndVerify: _unusedReconnect,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('升级后版本'), findsOneWidget);
    expect(find.text('2.5.1'), findsOneWidget);
    expect(find.text('开始升级'), findsOneWidget);
  });
}

FirmwarePackage _package() => FirmwarePackage(
  vendorId: 0x1234,
  productId: 0x5678,
  version: 5,
  expectedBusinessVersion: '2.5.1',
  payload: Uint8List.fromList(const [1, 2, 3]),
  expectedPayloadCrc32: 0x55BC801D,
  wqotaRequestPrefixFlags: const [0x70, 0x07, 0x6E, 0xC1],
  wqotaResponsePrefixFlags: const [0x70, 0x07, 0x6E, 0x01],
);

WqotaUpdateController _unusedController(FirmwarePackage _) =>
    throw UnimplementedError();

Future<void> _unusedReconnect(WqotaUpdateController _) async {}
