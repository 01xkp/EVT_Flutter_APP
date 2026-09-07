import 'package:aipin/core/ble/ble_transport.dart';
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
}
