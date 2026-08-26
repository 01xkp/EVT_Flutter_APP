import 'dart:async';

import 'package:aipin/features/local_recording/domain/audio_recorder_port.dart';

class FakeAudioRecorder implements AudioRecorderPort {
  final _signals = StreamController<RecorderSignal>.broadcast();
  final _amplitudes = StreamController<double>.broadcast();
  final List<String> operations = [];

  RecorderPermission permission = RecorderPermission.denied;
  Duration stopDuration = const Duration(seconds: 12);
  Object? startError;

  @override
  Stream<double> get amplitudes => _amplitudes.stream;

  @override
  Stream<RecorderSignal> get signals => _signals.stream;

  @override
  Future<void> dispose() async {
    await _signals.close();
    await _amplitudes.close();
  }

  void emit(RecorderSignal signal) => _signals.add(signal);

  void emitAmplitude(double amplitude) => _amplitudes.add(amplitude);

  @override
  Future<void> pause() async => operations.add('pause');

  @override
  Future<RecorderPermission> requestPermission() async => permission;

  @override
  Future<void> resume() async => operations.add('resume');

  @override
  Future<void> start(String temporaryPath) async {
    if (startError case final error?) {
      throw error;
    }
    operations.add('start');
  }

  @override
  Future<StoppedCapture> stop() async {
    operations.add('stop');
    return StoppedCapture(duration: stopDuration);
  }
}
