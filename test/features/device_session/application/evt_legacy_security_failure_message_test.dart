import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:aipin/core/protocol/evt_command_client.dart';
import 'package:aipin/features/device_session/application/evt_legacy_auth_controller.dart';
import 'package:aipin/features/device_session/application/evt_legacy_security_failure_message.dart';
import 'package:aipin/features/device_session/domain/evt_legacy_security_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses a clear timeout message for each V1 security action', () {
    final error = EvtCommandTimeoutException(0x09, 1);

    expect(
      evtLegacySecurityFailureMessage(
        action: EvtLegacySecurityAction.authenticate,
        error: error,
      ),
      '设备未返回认证结果，请重新连接后重试。',
    );
    expect(
      evtLegacySecurityFailureMessage(
        action: EvtLegacySecurityAction.bind,
        error: error,
      ),
      '设备未返回绑定结果，请重新连接后重试。',
    );
    expect(
      evtLegacySecurityFailureMessage(
        action: EvtLegacySecurityAction.reset,
        error: error,
      ),
      '设备未返回恢复结果，请重新连接后重试。',
    );
  });

  test('keeps safe device and transport failure messages', () {
    expect(
      evtLegacySecurityFailureMessage(
        action: EvtLegacySecurityAction.authenticate,
        error: const EvtLegacyAuthenticationException('设备拒绝认证码。'),
      ),
      '设备拒绝认证码。',
    );
    expect(
      evtLegacySecurityFailureMessage(
        action: EvtLegacySecurityAction.bind,
        error: BleTransportException(EvtFailure.transport(message: '蓝牙写入失败。')),
      ),
      '蓝牙写入失败。',
    );
  });

  test('does not expose unexpected exception text to users', () {
    expect(
      evtLegacySecurityFailureMessage(
        action: EvtLegacySecurityAction.authenticate,
        error: StateError('internal diagnostic detail'),
      ),
      '设备认证失败，请重新连接后重试。',
    );
  });
}
