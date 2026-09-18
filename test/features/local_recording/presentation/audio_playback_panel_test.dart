import 'dart:async';

import 'package:aipin/features/local_recording/domain/audio_player_port.dart';
import 'package:aipin/features/local_recording/presentation/audio_playback_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_audio_player.dart';

void main() {
  testWidgets('loads duration before play without starting audio', (
    tester,
  ) async {
    final player = FakeAudioPlayer()
      ..playDuration = const Duration(seconds: 20);
    await _open(tester, player);
    await tester.pump();
    expect(player.loadedPaths, ['/recordings/example.ogg']);
    expect(player.playedPaths, isEmpty);
    expect(find.text('0:20'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).max, 20000);
    await tester.drag(find.byType(Slider), const Offset(80, 0));
    await tester.pump();
    expect(player.seekedPositions.single, greaterThan(Duration.zero));
    expect(player.playedPaths, isEmpty);
  });

  testWidgets('waits for loading and does not play after leaving the page', (
    tester,
  ) async {
    final player = FakeAudioPlayer()..pendingLoad = Completer<Duration?>();
    await _open(tester, player);
    expect(find.text('读取中'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    player.pendingLoad!.complete(const Duration(seconds: 20));
    await tester.pump();
    expect(player.disposed, isTrue);
    expect(player.playedPaths, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unknown duration preserves real elapsed time and disables seeking',
    (tester) async {
      final player = FakeAudioPlayer();
      await _open(tester, player);
      await tester.pump();
      expect(find.text('时长未知'), findsOneWidget);
      await tester.tap(find.byTooltip('播放录音'));
      await tester.pump();
      player.emitPosition(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('0:03'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      player.emitState(AudioPlaybackState.completed);
      await tester.pump();
      expect(find.text('0:03'), findsOneWidget);
      player.emitDuration(const Duration(seconds: 20));
      await tester.pump();
      expect(find.text('0:20'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
    },
  );

  testWidgets(
    'progress only changes on player events and pauses without drift',
    (tester) async {
      final player = FakeAudioPlayer()
        ..playDuration = const Duration(seconds: 20);
      await _open(tester, player);
      await tester.pump();
      await tester.tap(find.byTooltip('播放录音'));
      await tester.pump();
      player.emitPosition(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.widget<Slider>(find.byType(Slider)).value, 3000);
      await tester.tap(find.byTooltip('暂停录音'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.widget<Slider>(find.byType(Slider)).value, 3000);
      await tester.tap(find.byTooltip('播放录音'));
      await tester.pump();
      player.emitPosition(const Duration(seconds: 4));
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 4000);
    },
  );

  testWidgets('failed preload can be retried by playing', (tester) async {
    final player = FakeAudioPlayer()..loadError = StateError('unreadable');
    await _open(tester, player);
    await tester.pump();
    expect(find.text('录音加载失败，请点击播放重试。'), findsOneWidget);
    expect(player.playedPaths, isEmpty);
    player.loadError = null;
    player.playDuration = const Duration(seconds: 20);
    await tester.tap(find.byTooltip('播放录音'));
    await tester.pump();
    await tester.pump();
    expect(find.text('0:20'), findsOneWidget);
    expect(player.playedPaths, ['/recordings/example.ogg']);
  });

  testWidgets('playback failure uses a toast instead of a SnackBar', (
    tester,
  ) async {
    final player = FakeAudioPlayer()
      ..playDuration = const Duration(seconds: 20)
      ..playError = StateError('decoder unavailable');
    await _open(tester, player);
    await tester.pump();

    await tester.tap(find.byTooltip('播放录音'));
    await tester.pump();

    expect(find.text('设备录音暂时无法播放。'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}

Future<void> _open(WidgetTester tester, FakeAudioPlayer player) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioPlaybackPanel(
            duration: Duration.zero,
            resolvePath: () async => '/recordings/example.ogg',
            audioPlayerFactory: () => player,
            playbackErrorMessage: '设备录音暂时无法播放。',
          ),
        ),
      ),
    );
