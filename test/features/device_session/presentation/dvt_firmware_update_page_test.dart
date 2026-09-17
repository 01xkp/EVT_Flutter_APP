import 'dart:async';
import 'dart:typed_data';

import 'package:aipin/core/protocol/wqota_codec.dart';
import 'package:aipin/features/device_session/application/wqota_update_controller.dart';
import 'package:aipin/features/device_session/domain/firmware_package.dart';
import 'package:aipin/features/device_session/domain/firmware_update_checkpoint.dart';
import 'package:aipin/features/device_session/domain/wqota_update_gateway.dart';
import 'package:aipin/features/device_session/presentation/dvt_firmware_update_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'does not start OTA when initialization finishes during back navigation',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final gateway = _Gateway();
      final controller = WqotaUpdateController(
        gateway: gateway,
        checkpoints: _Checkpoints(),
      );
      final creation = Completer<WqotaUpdateController>();
      final released = <WqotaUpdateController?>[];
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const Scaffold()),
      );
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => DvtFirmwareUpdatePage(
              deviceId: 'device-1',
              loadPackage: (_) async => _package(),
              createController: (_) => creation.future,
              createVerificationController: (_) => creation.future,
              releaseTransport: ({owner}) async => released.add(owner),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'https://example.test/fw');
      await tester.tap(find.text('读取并校验升级包'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始 / 恢复升级'));
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      // The route is still mounted while its reverse transition is running.
      expect(find.byType(DvtFirmwareUpdatePage), findsOneWidget);
      creation.complete(controller);
      await tester.pump();
      expect(gateway.prepareCount, 0);
      expect(released, contains(same(controller)));
      await tester.pumpAndSettle();
      expect(find.byType(DvtFirmwareUpdatePage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('releases the exact controller created by the OTA page', (
    tester,
  ) async {
    final controller = WqotaUpdateController(
      gateway: _Gateway(),
      checkpoints: _Checkpoints(),
      wait: (_) async {},
    );
    final released = <WqotaUpdateController?>[];
    final package = _package();

    await tester.pumpWidget(
      MaterialApp(
        home: DvtFirmwareUpdatePage(
          deviceId: 'device-1',
          loadPackage: (_) async => package,
          createController: (_) async => controller,
          createVerificationController: (_) async => controller,
          releaseTransport: ({owner}) async => released.add(owner),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'https://example.test/fw');
    await tester.tap(find.text('读取并校验升级包'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始 / 恢复升级'));
    await tester.pumpAndSettle();

    expect(controller.state.phase, WqotaUpdatePhase.awaitingReconnect);
    expect(released, hasLength(1));
    expect(released.single, same(controller));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

FirmwarePackage _package() => FirmwarePackage(
  vendorId: 0x1234,
  productId: 0x5678,
  version: 2,
  expectedBusinessVersion: '1.0.2',
  payload: Uint8List.fromList(const <int>[1, 2, 3]),
  expectedPayloadCrc32: 0x55BC801D,
  wireFormat: WqotaWireFormat.captured(
    captureId: 'dvt-v1.6-target-capture-001',
    requestPrefixFlags: const <int>[0x70, 0x07, 0x6E, 0xC1],
    responsePrefixFlags: const <int>[0x70, 0x07, 0x6E, 0x01],
  ),
  finalVerificationSupported: true,
);

class _Gateway implements WqotaUpdateGateway {
  var prepareCount = 0;

  @override
  Future<void> prepareTransport() async => prepareCount += 1;

  @override
  Future<WqotaDeviceIdentity> readDeviceIdentity() async =>
      const WqotaDeviceIdentity(vendorId: 0x1234, productId: 0x5678);

  @override
  Future<WqotaTransferWindow> queryFileInfoOffset() async =>
      const WqotaTransferWindow(offset: 0, length: 18);

  @override
  Future<void> inquireIfCanUpdate(Uint8List header) async {}

  @override
  Future<WqotaTransferWindow> enterUpdateMode() async =>
      const WqotaTransferWindow(offset: 18, length: 3);

  @override
  Future<WqotaTransferWindow> transferWindow({
    required int offset,
    required Uint8List bytes,
  }) async => const WqotaTransferWindow(offset: 0, length: 0);

  @override
  Future<void> refresh() async {}

  @override
  Future<WqotaImageVerificationState> readImageVerificationState() async =>
      WqotaImageVerificationState.verified;

  @override
  Future<void> reboot() async {}

  @override
  Future<void> exitUpdateMode() async {}

  @override
  Future<bool> verifyBusinessVersion(String expectedBusinessVersion) async =>
      true;
}

class _Checkpoints implements FirmwareUpdateCheckpointRepository {
  FirmwareUpdateCheckpoint? value;

  @override
  Future<void> clear(String deviceId) async => value = null;

  @override
  Future<FirmwareUpdateCheckpoint?> find(String deviceId) async => value;

  @override
  Future<void> save(FirmwareUpdateCheckpoint checkpoint) async =>
      value = checkpoint;
}
