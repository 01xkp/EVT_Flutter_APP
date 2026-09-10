import 'dart:async';
import 'dart:typed_data';

import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/diagnostics/diagnostic_sanitizer.dart';
import 'package:aipin/core/diagnostics/diagnostic_trace.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
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

  test(
    'native BLE diagnostics reduce fields and preserve valid packet hex',
    () {
      const deviceId = 'AA:BB:CC:DD:EE:FF';
      const characteristic = '0000FA19-1212-EFDE-1523-785FEABCD123';
      final fields = ReactiveBleTransport.nativeDiagnosticFieldsFor({
        'timestamp_ms': 1725872400123,
        'message': '【AIPIN原生BLE】【CCC配置完成】系统已完成 EVT 响应特征订阅',
        'raw_packet_hex': 'ed 04 00 89 01 2e ac',
        'fields': {
          'device_id': deviceId,
          'characteristic_uuid': characteristic,
          'instance_id': '42',
          'setup_completed': true,
          'packet_count': 3,
          'cccd_present': true,
          'cccd_required': true,
          'response_mode': 'indicate',
          'setup_mode': 'DEFAULT',
          'properties_hex': '0x28',
          'bytes': 99,
          'file_transfer': false,
          'raw_packet_hex_omitted': false,
          'error_type': 'none',
          'untrusted_value': 'must-not-persist',
        },
      });

      expect(fields['setup_mode'], 'DEFAULT');
      expect(fields['file_transfer'], isFalse);
      expect(fields['raw_packet_hex_omitted'], isFalse);
      expect(fields, <String, Object?>{
        'platform': 'android',
        'event_kind': 'native_ble',
        'reason': '【AIPIN原生BLE】【CCC配置完成】系统已完成 EVT 响应特征订阅',
        'occurred_at': 1725872400123,
        'device_suffix': '...EEFF',
        'characteristic': '0xFA19',
        'instance_id': 42,
        'setup_completed': true,
        'raw_packet_hex': 'ED 04 00 89 01 2E AC',
        'bytes': 7,
        'count': 3,
        'configured': true,
        'required': true,
        'requested_mode': 'indicate',
        'setup_mode': 'DEFAULT',
        'gatt_status': '0x28',
        'file_transfer': false,
        'raw_packet_hex_omitted': false,
        'error_type': 'none',
      });
      expect(fields.values.join(' '), isNot(contains(deviceId)));
      expect(fields.values.join(' '), isNot(contains(characteristic)));
      expect(fields, isNot(containsPair('untrusted_value', anything)));
      expect(
        const DiagnosticSanitizer().sanitize(scope: 'BLE', fields: fields),
        fields,
      );
    },
  );

  test('native BLE diagnostics discard malformed packet hex', () {
    final fields = ReactiveBleTransport.nativeDiagnosticFieldsFor({
      'raw_packet_hex': 'ED 04 00:89',
      'fields': const <String, Object?>{},
    });

    expect(fields, <String, Object?>{
      'platform': 'android',
      'event_kind': 'native_ble',
    });
  });

  test('native BLE diagnostics retain FF13 packet count and length safely', () {
    final fields = ReactiveBleTransport.nativeDiagnosticFieldsFor({
      'fields': {
        'packet_count': 100,
        'bytes': 244,
        'file_transfer': true,
        'raw_packet_hex_omitted': true,
      },
    });

    expect(fields, <String, Object?>{
      'platform': 'android',
      'event_kind': 'native_ble',
      'count': 100,
      'bytes': 244,
      'file_transfer': true,
      'raw_packet_hex_omitted': true,
    });
  });

  test(
    'native BLE diagnostics listener is cancelled when transport disposes',
    () async {
      final nativeEvents = StreamController<dynamic>.broadcast(sync: true);
      final logger = _RecordingLogger();
      final transport = ReactiveBleTransport(
        logger: logger,
        nativeBleLogStream: nativeEvents.stream,
        enableNativeBleLogBridge: true,
      );
      addTearDown(nativeEvents.close);
      addTearDown(transport.dispose);

      transport.startNativeBleLogBridgeForTesting();
      expect(nativeEvents.hasListener, isTrue);
      nativeEvents.add({
        'level': 'D',
        'event': 'characteristic_packet_received',
        'message': '【AIPIN原生BLE】【回包】收到设备原始数据',
        'raw_packet_hex': 'ED 04 00 89 01 2E AC',
        'fields': const <String, Object?>{
          'device_id': 'AA:BB:CC:DD:EE:FF',
          'characteristic_uuid': '0000FA19-1212-EFDE-1523-785FEABCD123',
        },
      });

      expect(logger.records, hasLength(1));
      expect(logger.records.single.event, 'characteristic_packet_received');
      expect(logger.records.single.fields['device_suffix'], '...EEFF');
      expect(logger.records.single.fields['characteristic'], '0xFA19');
      expect(
        logger.records.single.fields['raw_packet_hex'],
        'ED 04 00 89 01 2E AC',
      );

      await transport.dispose();
      expect(nativeEvents.hasListener, isFalse);
      nativeEvents.add({
        'level': 'D',
        'event': 'late_native_event',
        'fields': const <String, Object?>{},
      });
      transport.startNativeBleLogBridgeForTesting();

      expect(logger.records, hasLength(1));
      expect(nativeEvents.hasListener, isFalse);
    },
  );
}

class _RecordingLogger implements SafeAppLogger {
  final List<_LogRecord> records = [];

  @override
  void error(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) {
    records.add(_LogRecord(event, fields));
  }

  @override
  void info(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) {
    records.add(_LogRecord(event, fields));
  }

  @override
  void warning(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) {
    records.add(_LogRecord(event, fields));
  }
}

class _LogRecord {
  const _LogRecord(this.event, this.fields);

  final String event;
  final Map<String, Object?> fields;
}
