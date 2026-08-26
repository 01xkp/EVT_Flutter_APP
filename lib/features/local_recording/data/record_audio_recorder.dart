import 'dart:async';

import 'package:aipin/features/local_recording/domain/audio_recorder_port.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart' as record;

class RecordAudioRecorder implements AudioRecorderPort {
  RecordAudioRecorder({
    record.AudioRecorder? recorder,
    record.RecordConfig? config,
  }) : _recorder = recorder ?? record.AudioRecorder(),
       _config = config ?? localRecordConfig {
    _stateSubscription = _recorder.onStateChanged().listen(
      _onRecordState,
      onError: _onStateError,
    );
  }

  static const localRecordConfig = record.RecordConfig(
    encoder: record.AudioEncoder.aacLc,
    bitRate: 64000,
    sampleRate: 44100,
    numChannels: 1,
    autoGain: true,
    echoCancel: true,
    noiseSuppress: true,
  );

  final record.AudioRecorder _recorder;
  final record.RecordConfig _config;
  final _signals = StreamController<RecorderSignal>.broadcast();
  late final StreamSubscription<record.RecordState> _stateSubscription;
  Stopwatch? _stopwatch;
  var _captureActive = false;
  var _expectedStop = false;
  var _disposed = false;

  @override
  Stream<double> get amplitudes => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 240))
      .map((value) => ((value.current + 60) / 60).clamp(0.0, 1.0));

  @override
  Stream<RecorderSignal> get signals => _signals.stream;

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _stateSubscription.cancel();
    await _signals.close();
    await _recorder.dispose();
  }

  @override
  Future<void> pause() async {
    await _recorder.pause();
    _stopwatch?.stop();
  }

  @override
  Future<RecorderPermission> requestPermission() async {
    if (await _recorder.hasPermission()) {
      return RecorderPermission.granted;
    }
    final status = await Permission.microphone.status;
    return status.isPermanentlyDenied
        ? RecorderPermission.permanentlyDenied
        : RecorderPermission.denied;
  }

  @override
  Future<void> resume() async {
    await _recorder.resume();
    _stopwatch?.start();
  }

  @override
  Future<void> start(String temporaryPath) async {
    if (!await _recorder.hasPermission(request: false)) {
      throw const RecorderPermissionException();
    }
    await _recorder.start(_config, path: temporaryPath);
    _stopwatch = Stopwatch()..start();
    _captureActive = true;
    _expectedStop = false;
  }

  @override
  Future<StoppedCapture> stop() async {
    _expectedStop = true;
    try {
      await _recorder.stop();
      _stopwatch?.stop();
      return StoppedCapture(duration: _stopwatch?.elapsed ?? Duration.zero);
    } finally {
      _captureActive = false;
    }
  }

  void _onRecordState(record.RecordState state) {
    if (state == record.RecordState.stop &&
        _captureActive &&
        !_expectedStop &&
        !_disposed) {
      _captureActive = false;
      _stopwatch?.stop();
      _signals.add(const RecorderSignal.interrupted('系统音频中断'));
    }
  }

  void _onStateError(Object error, StackTrace stackTrace) {
    if (_captureActive && !_disposed) {
      _signals.add(const RecorderSignal.interrupted('系统音频中断'));
    }
  }
}
