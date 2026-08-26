import 'package:aipin/features/local_recording/domain/recording_background_port.dart';

class FakeRecordingBackgroundService implements RecordingBackgroundPort {
  int startCalls = 0;
  int stopCalls = 0;
  final List<Duration> elapsedUpdates = [];

  @override
  Future<void> start() async => startCalls += 1;

  @override
  Future<void> stop() async => stopCalls += 1;

  @override
  Future<void> updateElapsed(Duration elapsed) async {
    elapsedUpdates.add(elapsed);
  }
}
