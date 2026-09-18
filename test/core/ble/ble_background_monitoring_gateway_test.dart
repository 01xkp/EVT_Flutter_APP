import 'dart:async';

import 'package:aipin/core/ble/ble_background_monitoring_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BleBackgroundMonitoringController', () {
    test('starts once for an eligible foreground GATT session', () async {
      final gateway = _FakeBleBackgroundMonitoringGateway();
      final controller = BleBackgroundMonitoringController(gateway);

      await controller.updateForSession(
        shouldMonitor: true,
        deviceId: '71:BF:E2:3B:84:23',
        deviceName: 'AIPIN_8423',
      );
      await controller.updateForSession(
        shouldMonitor: true,
        deviceId: '71:BF:E2:3B:84:23',
        deviceName: 'AIPIN_8423',
      );

      expect(gateway.started, hasLength(1));
      expect(gateway.started.single.deviceId, '71:BF:E2:3B:84:23');
      expect(gateway.started.single.deviceName, 'AIPIN_8423');
      expect(controller.isActive, isTrue);
    });

    test('stops when the monitored GATT session is no longer usable', () async {
      final gateway = _FakeBleBackgroundMonitoringGateway();
      final controller = BleBackgroundMonitoringController(gateway);
      await controller.updateForSession(
        shouldMonitor: true,
        deviceId: '71:BF:E2:3B:84:23',
        deviceName: 'AIPIN_8423',
      );

      await controller.updateForSession(shouldMonitor: false);

      expect(gateway.stopCount, 1);
      expect(controller.isActive, isFalse);
    });

    test(
      'defers a new Android service start until the app is foreground',
      () async {
        final gateway = _FakeBleBackgroundMonitoringGateway();
        final controller = BleBackgroundMonitoringController(gateway);

        await controller.updateForSession(
          shouldMonitor: true,
          deviceId: '71:BF:E2:3B:84:23',
          deviceName: 'AIPIN_8423',
          canStart: false,
        );

        expect(gateway.started, isEmpty);
        expect(controller.isActive, isFalse);

        await controller.updateForSession(
          shouldMonitor: true,
          deviceId: '71:BF:E2:3B:84:23',
          deviceName: 'AIPIN_8423',
          canStart: true,
        );

        expect(gateway.started, hasLength(1));
        expect(controller.isActive, isTrue);
      },
    );

    test('serializes a pending start followed by a disconnect stop', () async {
      final gateway = _FakeBleBackgroundMonitoringGateway(deferStart: true);
      final controller = BleBackgroundMonitoringController(gateway);

      final start = controller.updateForSession(
        shouldMonitor: true,
        deviceId: '71:BF:E2:3B:84:23',
        deviceName: 'AIPIN_8423',
      );
      await Future<void>.delayed(Duration.zero);
      final stop = controller.updateForSession(shouldMonitor: false);
      gateway.completeStart();

      await Future.wait<void>(<Future<void>>[start, stop]);

      expect(gateway.started, hasLength(1));
      expect(gateway.stopCount, 1);
      expect(controller.isActive, isFalse);
    });

    test('requires a stable device identity before enabling monitoring', () {
      final controller = BleBackgroundMonitoringController(
        _FakeBleBackgroundMonitoringGateway(),
      );

      expect(
        () => controller.updateForSession(
          shouldMonitor: true,
          deviceId: '',
          deviceName: 'AIPIN_8423',
        ),
        throwsArgumentError,
      );
    });

    test(
      'retries activation after a native foreground-service failure',
      () async {
        final gateway = _FakeBleBackgroundMonitoringGateway(failStarts: 1);
        final controller = BleBackgroundMonitoringController(gateway);

        await controller.updateForSession(
          shouldMonitor: true,
          deviceId: '71:BF:E2:3B:84:23',
          deviceName: 'AIPIN_8423',
        );
        expect(controller.isActive, isFalse);
        expect(gateway.startCount, 1);

        await controller.updateForSession(
          shouldMonitor: true,
          deviceId: '71:BF:E2:3B:84:23',
          deviceName: 'AIPIN_8423',
        );
        expect(controller.isActive, isTrue);
        expect(gateway.startCount, 2);
      },
    );
  });
}

class _FakeBleBackgroundMonitoringGateway
    implements BleBackgroundMonitoringGateway {
  _FakeBleBackgroundMonitoringGateway({
    this.deferStart = false,
    this.failStarts = 0,
  });

  final bool deferStart;
  int failStarts;
  final List<BleBackgroundMonitoringRequest> started =
      <BleBackgroundMonitoringRequest>[];
  final _startCompleter = Completer<void>();
  var stopCount = 0;
  var startCount = 0;

  @override
  Future<void> start(BleBackgroundMonitoringRequest request) async {
    startCount += 1;
    if (failStarts > 0) {
      failStarts -= 1;
      throw StateError('native foreground service rejected');
    }
    started.add(request);
    if (deferStart) {
      await _startCompleter.future;
    }
  }

  void completeStart() {
    if (!_startCompleter.isCompleted) {
      _startCompleter.complete();
    }
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }
}
