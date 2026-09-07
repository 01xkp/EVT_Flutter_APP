import 'package:aipin/core/permissions/app_permission_gateway.dart';
import 'package:aipin/core/permissions/permission_handler_gateway.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' as reactive;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps iOS CoreBluetooth status for the nearby devices setting', () {
    expect(
      PermissionHandlerGateway.nearbyDevicesStateForIosBleStatus(
        reactive.BleStatus.ready,
      ),
      AppPermissionState.granted,
    );
    expect(
      PermissionHandlerGateway.nearbyDevicesStateForIosBleStatus(
        reactive.BleStatus.poweredOff,
      ),
      AppPermissionState.granted,
    );
    expect(
      PermissionHandlerGateway.nearbyDevicesStateForIosBleStatus(
        reactive.BleStatus.unauthorized,
      ),
      AppPermissionState.permanentlyDenied,
    );
    expect(
      PermissionHandlerGateway.nearbyDevicesStateForIosBleStatus(
        reactive.BleStatus.unsupported,
      ),
      AppPermissionState.unavailable,
    );
  });
}
