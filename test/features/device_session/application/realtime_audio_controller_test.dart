import 'dart:async';
import 'dart:typed_data';

import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:aipin/features/device_session/application/realtime_audio_controller.dart';
import 'package:aipin/features/device_session/domain/realtime_audio_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'captures ordered 0x08 payloads and closes the device stream cleanly',
    () async {
      final gateway = _AudioGateway();
      final codec = EvtProtocolCodec();
      final controller = RealtimeAudioController(
        gateway: gateway,
        codec: codec,
      );
      addTearDown(() async {
        await controller.dispose();
        await gateway.close();
      });

      await controller.start();
      gateway.emit(codec.encodeRequest(0x08, const [1, 2]));
      gateway.emit(codec.encodeRequest(0x08, const [3, 4, 5]));
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.phase, RealtimeAudioPhase.capturing);
      expect(controller.state.receivedBytes, 5);
      expect(
        controller.captureBytes(),
        Uint8List.fromList(const [1, 2, 3, 4, 5]),
      );

      await controller.stop();

      expect(controller.state.phase, RealtimeAudioPhase.completed);
      expect(gateway.operations, [
        'stream:true',
        'record:true',
        'stream:false',
        'record:false',
      ]);
    },
  );

  test(
    'disables the stream and reports a recoverable error when the capture bound is exceeded',
    () async {
      final gateway = _AudioGateway();
      final codec = EvtProtocolCodec();
      final controller = RealtimeAudioController(
        gateway: gateway,
        codec: codec,
        maximumCaptureBytes: 3,
      );
      addTearDown(() async {
        await controller.dispose();
        await gateway.close();
      });

      await controller.start();
      gateway.emit(codec.encodeRequest(0x08, const [1, 2, 3, 4]));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.phase, RealtimeAudioPhase.failed);
      expect(controller.state.error, contains('上限'));
      expect(controller.state.receivedBytes, 0);
      expect(gateway.operations, contains('stream:false'));
    },
  );
}

class _AudioGateway implements RealtimeAudioGateway {
  final _frames = StreamController<Uint8List>.broadcast();
  final operations = <String>[];

  @override
  Stream<Uint8List> subscribeRealtimeAudio() => _frames.stream;

  @override
  Future<void> setAudioStreamEnabled(bool enabled) async {
    operations.add('stream:$enabled');
  }

  @override
  Future<void> setRealtimeRecording(bool active) async {
    operations.add('record:$active');
  }

  void emit(List<int> frame) => _frames.add(Uint8List.fromList(frame));

  Future<void> close() => _frames.close();
}
