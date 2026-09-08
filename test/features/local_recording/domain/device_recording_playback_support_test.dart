import 'package:aipin/features/local_recording/domain/device_recording_playback_support.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LocalRecording saved(String path) => LocalRecording.saved(
    id: 'recording',
    title: 'device recording',
    relativePath: path,
    createdAt: DateTime.utc(2026),
    completedAt: DateTime.utc(2026),
    duration: const Duration(seconds: 1),
    sizeBytes: 1,
  );

  test('does not expose Ogg/Opus playback on iOS', () {
    final recording = saved('device-recording.ogg');

    expect(
      DeviceRecordingPlaybackSupport.canPlay(recording, isIOS: true),
      isFalse,
    );
    expect(
      DeviceRecordingPlaybackSupport.unavailableMessage(recording, isIOS: true),
      contains('iOS'),
    );
  });

  test('keeps M4A and Android Ogg playback available', () {
    expect(
      DeviceRecordingPlaybackSupport.canPlay(
        saved('device-recording.m4a'),
        isIOS: true,
      ),
      isTrue,
    );
    expect(
      DeviceRecordingPlaybackSupport.canPlay(
        saved('device-recording.ogg'),
        isIOS: false,
      ),
      isTrue,
    );
  });
}
