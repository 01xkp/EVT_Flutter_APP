import 'dart:async';
import 'dart:typed_data';

import 'package:aipin/features/device_session/application/dvt_audio_probe_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('startup cleanup failure retains an explicit stop action', () async {
    final payloads = StreamController<Uint8List>.broadcast(sync: true);
    var stopCount = 0;
    final controller = DvtAudioProbeController(
      validatedAudioPayloads: payloads.stream,
      startDvtAudioProbe: () async {
        payloads.add(Uint8List(480));
        payloads.addError(StateError('FA18 failed during start'));
      },
      stopDvtAudioProbe: () async {
        if (++stopCount == 1) throw StateError('cleanup was not confirmed');
      },
    );
    await controller.start();
    expect(controller.state.phase, DvtAudioProbePhase.failed);
    expect(controller.state.canStop, isTrue);
    expect(controller.state.canStart, isFalse);
    expect(controller.state.frameCount, 1);
    await controller.stop();
    expect(stopCount, 2);
    expect(controller.state.phase, DvtAudioProbePhase.completed);
    controller.dispose();
    await payloads.close();
  });

  test(
    'forced disposal during start still disables the device stream',
    () async {
      final payloads = StreamController<Uint8List>();
      final starting = Completer<void>();
      final stopped = Completer<void>();
      final controller = DvtAudioProbeController(
        validatedAudioPayloads: payloads.stream,
        startDvtAudioProbe: () => starting.future,
        stopDvtAudioProbe: () async => stopped.complete(),
      );
      final operation = controller.start();
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      starting.complete();
      await operation;
      await stopped.future.timeout(const Duration(seconds: 1));
      await payloads.close();
    },
  );

  test(
    'counts early data without rebuilding UI for every audio frame',
    () async {
      final payloads = StreamController<Uint8List>(sync: true);
      final controller = DvtAudioProbeController(
        validatedAudioPayloads: payloads.stream,
        startDvtAudioProbe: () async => payloads.add(Uint8List(480)),
        stopDvtAudioProbe: () async {},
      );
      var notifications = 0;
      controller.addListener(() => notifications++);
      await controller.start();
      expect(controller.state.frameCount, 1);
      final initial = notifications;
      for (var i = 0; i < 100; i++) {
        payloads.add(Uint8List(480));
      }
      expect(controller.state.frameCount, 101);
      expect(notifications, initial);
      await controller.stop();
      controller.dispose();
      await payloads.close();
    },
  );

  test(
    'listens before start and reports received frames, bytes and throughput',
    () async {
      final payloads = StreamController<Uint8List>(sync: true);
      var listenerCount = 0;
      payloads.onListen = () => listenerCount += 1;
      var startCount = 0;
      var stopCount = 0;
      var now = DateTime.utc(2026, 9, 15, 9, 0);
      final controller = DvtAudioProbeController(
        validatedAudioPayloads: payloads.stream,
        startDvtAudioProbe: () async {
          expect(listenerCount, 1);
          startCount += 1;
        },
        stopDvtAudioProbe: () async => stopCount += 1,
        clock: () => now,
      );

      await controller.start();

      expect(startCount, 1);
      expect(controller.state.phase, DvtAudioProbePhase.streaming);
      expect(controller.state.frameCount, 0);
      now = now.add(const Duration(seconds: 2));
      payloads.add(Uint8List.fromList(const [1, 2, 3, 4, 5, 6, 7, 8]));

      expect(controller.state.frameCount, 1);
      expect(controller.state.byteCount, 8);
      expect(controller.state.elapsed, const Duration(seconds: 2));
      expect(controller.state.bytesPerSecond, 4);
      expect(
        DvtAudioProbeState.packetLossUnavailableMessage,
        contains('无法计算丢包率'),
      );

      await controller.stop();

      expect(stopCount, 1);
      expect(controller.state.phase, DvtAudioProbePhase.completed);
      expect(controller.state.mayRequireStop, isFalse);
      controller.dispose();
      await payloads.close();
    },
  );

  test(
    'keeps the stop path available when the audio notification stream fails',
    () async {
      final payloads = StreamController<Uint8List>(sync: true);
      var stopCount = 0;
      final controller = DvtAudioProbeController(
        validatedAudioPayloads: payloads.stream,
        startDvtAudioProbe: () async {},
        stopDvtAudioProbe: () async => stopCount += 1,
      );

      await controller.start();
      payloads.addError(StateError('FA18 stream closed unexpectedly'));

      expect(controller.state.phase, DvtAudioProbePhase.failed);
      expect(controller.state.canStop, isTrue);
      expect(controller.state.canStart, isFalse);

      await controller.stop();

      expect(stopCount, 1);
      expect(controller.state.phase, DvtAudioProbePhase.completed);
      controller.dispose();
      await payloads.close();
    },
  );

  test(
    'reports a start failure without marking the stream as active',
    () async {
      final payloads = StreamController<Uint8List>(sync: true);
      final controller = DvtAudioProbeController(
        validatedAudioPayloads: payloads.stream,
        startDvtAudioProbe: () async {
          throw StateError('FA18 CCC was not enabled');
        },
        stopDvtAudioProbe: () async {},
      );

      await controller.start();

      expect(controller.state.phase, DvtAudioProbePhase.failed);
      expect(controller.state.mayRequireStop, isFalse);
      expect(controller.state.canStart, isTrue);
      controller.dispose();
      await payloads.close();
    },
  );
}
