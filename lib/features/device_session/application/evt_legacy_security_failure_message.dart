import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/protocol/evt_command_client.dart';
import 'package:aipin/features/device_session/application/evt_legacy_auth_controller.dart';
import 'package:aipin/features/device_session/domain/evt_legacy_security_gateway.dart';

/// Keeps transport and protocol internals out of the EVT security UI.
String evtLegacySecurityFailureMessage({
  required EvtLegacySecurityAction action,
  required Object error,
}) {
  if (error is EvtCommandTimeoutException) {
    return switch (action) {
      EvtLegacySecurityAction.authenticate => '设备未返回认证结果，请重新连接后重试。',
      EvtLegacySecurityAction.bind => '设备未返回绑定结果，请重新连接后重试。',
      EvtLegacySecurityAction.reset => '设备未返回恢复结果，请重新连接后重试。',
    };
  }
  if (error is EvtLegacyAuthenticationException) {
    return error.message;
  }
  if (error is BleTransportException) {
    return error.failure.message;
  }
  return switch (action) {
    EvtLegacySecurityAction.authenticate => '设备认证失败，请重新连接后重试。',
    EvtLegacySecurityAction.bind => '设备绑定失败，请重新连接后重试。',
    EvtLegacySecurityAction.reset => '恢复初始认证码失败，请重新连接后重试。',
  };
}
