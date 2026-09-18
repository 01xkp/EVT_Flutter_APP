import 'package:aipin/features/local_recording/domain/audio_player_port.dart';
import 'package:aipin/features/local_recording/domain/device_recording_playback_support.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/domain/recording_file_store.dart';
import 'package:aipin/features/local_recording/presentation/audio_playback_panel.dart';
import 'package:flutter/material.dart';

/// Playback is available only for audio received through the EVT device-file
/// transfer flow. This page intentionally has no microphone, AI, or document
/// processing actions.
class DeviceRecordingDetailPage extends StatelessWidget {
  const DeviceRecordingDetailPage({
    super.key,
    required this.recording,
    required this.files,
    required this.audioPlayerFactory,
    this.recordings = const <LocalRecording>[],
    this.onOpenRecording,
  });

  final LocalRecording recording;
  final RecordingFileStore files;
  final AudioPlayerPort Function() audioPlayerFactory;
  final List<LocalRecording> recordings;
  final ValueChanged<LocalRecording>? onOpenRecording;

  @override
  Widget build(BuildContext context) {
    final duration = recording.duration;
    final canPlay = DeviceRecordingPlaybackSupport.canPlay(recording);
    return Scaffold(
      appBar: AppBar(title: Text(recording.title)),
      body: !canPlay || duration == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  DeviceRecordingPlaybackSupport.unavailableMessage(recording),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : AudioPlaybackPanel(
              key: ValueKey(recording.id),
              duration: duration,
              resolvePath: () => files.absolutePathFor(recording.relativePath),
              audioPlayerFactory: audioPlayerFactory,
              playbackErrorMessage: '设备录音暂时无法播放。',
              progressKey: const ValueKey('device-recording-playback-progress'),
              waveformKey: const ValueKey('device-recording-playback-waveform'),
              onPrevious: _previousRecording == null || onOpenRecording == null
                  ? null
                  : () => onOpenRecording!(_previousRecording!),
              onNext: _nextRecording == null || onOpenRecording == null
                  ? null
                  : () => onOpenRecording!(_nextRecording!),
            ),
    );
  }

  LocalRecording? get _previousRecording {
    final index = _recordingIndex;
    return index > 0 ? recordings[index - 1] : null;
  }

  LocalRecording? get _nextRecording {
    final index = _recordingIndex;
    return index >= 0 && index + 1 < recordings.length
        ? recordings[index + 1]
        : null;
  }

  int get _recordingIndex =>
      recordings.indexWhere((item) => item.id == recording.id);
}
