import 'package:aipin/features/local_recording/domain/audio_player_port.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/presentation/device_recording_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_audio_player.dart';
import '../../../support/fake_recording_file_store.dart';

void main() {
  testWidgets('plays a saved device recording and seeks its progress', (
    tester,
  ) async {
    final player = FakeAudioPlayer();
    await tester.pumpWidget(
      MaterialApp(home: _detailPage(audioPlayerFactory: () => player)),
    );

    final waveform = find.byKey(
      const ValueKey('device-recording-playback-waveform'),
    );
    final progress = find.byKey(
      const ValueKey('device-recording-playback-progress'),
    );
    expect(waveform, findsOneWidget);
    expect(progress, findsOneWidget);
    expect(find.descendant(of: waveform, matching: progress), findsNothing);

    await tester.pump();
    await tester.tap(find.byTooltip('播放录音'));
    await tester.pump();
    player.emitPosition(const Duration(seconds: 3));
    await tester.pump();
    await tester.drag(progress, const Offset(120, 0));
    await tester.pump();

    expect(player.playedPaths, <String>['/recordings/recording-1.m4a']);
    expect(player.seekedPositions, isNotEmpty);
  });

  testWidgets(
    'uses the duration parsed after opening an imported device recording',
    (tester) async {
      final player = FakeAudioPlayer()
        ..playDuration = const Duration(seconds: 12);
      await tester.pumpWidget(
        MaterialApp(
          home: _detailPage(
            audioPlayerFactory: () => player,
            recording: _savedRecording(duration: Duration.zero),
          ),
        ),
      );

      final progress = find.byKey(
        const ValueKey('device-recording-playback-progress'),
      );
      expect(tester.widget<Slider>(progress).max, 1);

      await tester.pump();

      expect(tester.widget<Slider>(progress).max, 12000);
      expect(find.text('0:12'), findsOneWidget);
      expect(player.loadedPaths, <String>['/recordings/recording-1.m4a']);
      expect(player.playedPaths, isEmpty);

      await tester.tap(find.byTooltip('播放录音'));
      await tester.pump();

      player.emitPosition(const Duration(seconds: 3));
      await tester.pump();

      expect(tester.widget<Slider>(progress).value, 3000);
    },
  );

  testWidgets('shows a retryable decode failure before playback starts', (
    tester,
  ) async {
    final player = FakeAudioPlayer()..loadError = StateError('decode failed');
    await tester.pumpWidget(
      MaterialApp(home: _detailPage(audioPlayerFactory: () => player)),
    );
    await tester.pump();

    expect(find.text('录音加载失败，请点击播放重试。'), findsOneWidget);
    expect(player.playedPaths, isEmpty);

    await tester.tap(find.byTooltip('播放录音'));
    await tester.pump();

    expect(player.loadedPaths, hasLength(2));
    expect(player.playedPaths, isEmpty);
  });

  testWidgets('opens adjacent saved device recordings from skip controls', (
    tester,
  ) async {
    LocalRecording? opened;
    final first = _savedRecording(id: 'recording-1', title: '第一条录音');
    final current = _savedRecording(id: 'recording-2', title: '第二条录音');
    final last = _savedRecording(id: 'recording-3', title: '第三条录音');
    await tester.pumpWidget(
      MaterialApp(
        home: _detailPage(
          recording: current,
          recordings: [first, current, last],
          onOpenRecording: (recording) => opened = recording,
        ),
      ),
    );

    await tester.tap(find.byTooltip('上一条录音'));
    expect(opened?.id, 'recording-1');
    await tester.tap(find.byTooltip('下一条录音'));
    expect(opened?.id, 'recording-3');
  });
}

Widget _detailPage({
  AudioPlayerPort Function()? audioPlayerFactory,
  LocalRecording? recording,
  List<LocalRecording> recordings = const <LocalRecording>[],
  ValueChanged<LocalRecording>? onOpenRecording,
}) {
  return DeviceRecordingDetailPage(
    recording: recording ?? _savedRecording(),
    recordings: recordings,
    onOpenRecording: onOpenRecording,
    files: FakeRecordingFileStore(),
    audioPlayerFactory: audioPlayerFactory ?? FakeAudioPlayer.new,
  );
}

LocalRecording _savedRecording({
  String id = 'recording-1',
  String title = '设备录音',
  Duration duration = const Duration(seconds: 12),
}) {
  return LocalRecording.saved(
    id: id,
    title: title,
    relativePath: '$id.m4a',
    createdAt: DateTime(2026, 8, 25),
    completedAt: DateTime(2026, 8, 25, 0, 0, 12),
    duration: duration,
    sizeBytes: 160000,
  );
}
