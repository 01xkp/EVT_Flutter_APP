import 'dart:typed_data';

import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/diagnostics/diagnostic_sanitizer.dart';
import 'package:aipin/core/ble/reactive_ble_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' as reactive;

void main() {
  test('does not gate iOS scans on PermissionHandler Bluetooth requests', () {
    expect(
      ReactiveBleTransport.requiresPermissionHandlerScanRequest(
        isAndroid: false,
        isIOS: true,
      ),
      isFalse,
    );
  });

  test('uses the plugin-reported ATT MTU without platform adjustment', () {
    expect(ReactiveBleTransport.attMtuFromPlugin(27), 27);
    expect(ReactiveBleTransport.attMtuFromPlugin(185), 185);
  });

  test('converts the iOS write payload capacity to ATT MTU', () {
    final converter = ReactiveBleTransport.attMtuFromPlugin as dynamic;
    Object? converted;

    expect(
      () => converted = Function.apply(
        converter,
        [133],
        {#reportedAsWritePayload: true},
      ),
      returnsNormally,
    );
    expect(converted, 136);
  });

  test('retries only an iOS default MTU payload report', () {
    expect(
      ReactiveBleTransport.shouldRetryIosMtuReport(20, isIOS: true),
      isTrue,
    );
    expect(
      ReactiveBleTransport.shouldRetryIosMtuReport(21, isIOS: true),
      isFalse,
    );
    expect(
      ReactiveBleTransport.shouldRetryIosMtuReport(20, isIOS: false),
      isFalse,
    );
  });

  test('maps an encrypted GATT denial to explicit system pairing guidance', () {
    final failure = ReactiveBleTransport.gattOperationFailure(
      StateError('GATT_INSUFFICIENT_AUTHENTICATION status=5'),
      fallbackMessage: '蓝牙写入失败。',
    );

    expect(failure.kind.name, 'transport');
    expect(failure.message, '设备需要完成系统配对。');
    expect(failure.detail, contains('系统弹窗'));
  });

  test('keeps unrelated GATT operation failures diagnostic', () {
    final failure = ReactiveBleTransport.gattOperationFailure(
      StateError('GATT status=133'),
      fallbackMessage: '蓝牙写入失败。',
    );

    expect(failure.kind.name, 'transport');
    expect(failure.message, '蓝牙写入失败。');
    expect(failure.detail, contains('status=133'));
  });

  test('maps every non-ready BLE status to actionable scan guidance', () {
    final poweredOff = ReactiveBleTransport.scanFailureForStatus(
      reactive.BleStatus.poweredOff,
    );
    expect(poweredOff?.issue, BleTransportIssue.bluetoothOff);
    expect(poweredOff?.failure.message, '蓝牙未开启。');

    expect(
      ReactiveBleTransport.scanFailureForStatus(
        reactive.BleStatus.unsupported,
      )?.failure.message,
      '当前设备不支持低功耗蓝牙。',
    );
    expect(
      ReactiveBleTransport.scanFailureForStatus(
        reactive.BleStatus.unauthorized,
      )?.failure.message,
      '请在系统设置中允许本应用使用蓝牙。',
    );
    expect(
      ReactiveBleTransport.scanFailureForStatus(
        reactive.BleStatus.locationServicesDisabled,
      )?.failure.message,
      '请开启系统定位服务后重新查找设备。',
    );
    expect(
      ReactiveBleTransport.scanFailureForStatus(reactive.BleStatus.ready),
      isNull,
    );
  });

  test(
    'Debug transport diagnostics retain one complete physical packet hex field',
    () {
      final summary = ReactiveBleTransport.safeByteSummaryForDiagnostics(
        Uint8List.fromList(const [
          0xED,
          0x09,
          0x00,
          0x09,
          0x11,
          0x22,
          0x33,
          0x44,
          0x55,
          0x66,
          0x00,
          0x00,
        ]),
      );

      expect(summary, <String, Object?>{
        'bytes': 12,
        'type': 'binary_full',
        'raw_packet_hex': 'ED 09 00 09 11 22 33 44 55 66 00 00',
      });
      expect(summary.values.join(), contains('11 22 33 44 55 66'));
      expect(
        summary.keys.where((key) => key == 'raw_packet_hex'),
        hasLength(1),
      );
      expect(
        const DiagnosticSanitizer().sanitize(scope: 'BLE', fields: summary),
        summary,
      );
      expect(
        const DiagnosticSanitizer(
          allowDebugRawPacketHex: false,
        ).sanitize(scope: 'BLE', fields: summary),
        <String, Object?>{'bytes': 12, 'type': 'binary_full'},
      );
    },
  );

  test('uses EVT characteristic short codes in physical packet logs', () {
    expect(
      ReactiveBleTransport.safeCharacteristicReferenceForDiagnostics(
        '0000FA19-1212-EFDE-1523-785FEABCD123',
      ),
      '0xFA19',
    );
    expect(
      ReactiveBleTransport.safeCharacteristicReferenceForDiagnostics(
        '0000FF13-1212-EFDE-1523-785FEABCD123',
      ),
      '0xFF13',
    );
  });

  test('transport device reference does not retain a full MAC address', () {
    const rawDeviceId = 'AA:BB:CC:DD:EE:FF';
    final reference = ReactiveBleTransport.safeDeviceReferenceForDiagnostics(
      rawDeviceId,
    );

    expect(reference, '...EEFF');
    expect(reference, isNot(contains(rawDeviceId)));
    expect(reference, isNot(contains(':')));
    expect(
      const DiagnosticSanitizer().sanitize(
        scope: 'BLE',
        fields: {'device_suffix': reference},
      ),
      {'device_suffix': reference},
    );
  });
}
