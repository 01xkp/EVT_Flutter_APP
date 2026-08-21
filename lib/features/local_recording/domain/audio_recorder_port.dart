enum RecorderPermission { granted, denied, permanentlyDenied }

sealed class RecorderSignal {
  const RecorderSignal();

  const factory RecorderSignal.interrupted(String reason) = RecorderInterrupted;
}

class RecorderInterrupted extends RecorderSignal {
  const RecorderInterrupted(this.reason);

  final String reason;
}

class StoppedCapture {
  const StoppedCapture({required this.duration});

  final Duration duration;
}

class RecorderPermissionException implements Exception {
  const RecorderPermissionException();
}

abstract interface class AudioRecorderPort {
  Future<RecorderPermission> requestPermission();
  Stream<RecorderSignal> get signals;
  Stream<double> get amplitudes;
  Future<void> start(String temporaryPath);
  Future<void> pause();
  Future<void> resume();
  Future<StoppedCapture> stop();
  Future<void> dispose();
}
