abstract interface class RecordingBackgroundPort {
  Future<void> start();
  Future<void> updateElapsed(Duration elapsed);
  Future<void> stop();
}
