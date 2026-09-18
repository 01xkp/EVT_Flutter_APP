import 'dart:async';

import 'package:aipin/features/local_recording/data/just_audio_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as native;

void main() {
  test(
    'preload reads duration silently and play reuses the prepared source',
    () async {
      final engine = _Engine();
      final player = JustAudioPlayer(player: engine);
      expect(await player.load('/tmp/one.ogg'), const Duration(seconds: 20));
      expect(engine.calls, ['stop', 'load:/tmp/one.ogg']);
      await player.play('/tmp/one.ogg');
      expect(engine.calls, ['stop', 'load:/tmp/one.ogg', 'play']);
      await player.load('/tmp/two.ogg');
      expect(engine.calls.sublist(3), ['stop', 'load:/tmp/two.ogg']);
      await player.dispose();
    },
  );

  test('failed preload does not cache the source and allows retry', () async {
    final engine = _Engine()..failLoad = true;
    final player = JustAudioPlayer(player: engine);
    await expectLater(player.load('/tmp/one.ogg'), throwsStateError);
    engine.failLoad = false;
    await player.play('/tmp/one.ogg');
    expect(engine.calls, [
      'stop',
      'load:/tmp/one.ogg',
      'stop',
      'load:/tmp/one.ogg',
      'play',
    ]);
    await player.dispose();
  });

  test('disposing during load prevents a late play', () async {
    final engine = _Engine()..pendingLoad = Completer<Duration?>();
    final player = JustAudioPlayer(player: engine);
    final playing = player.play('/tmp/one.ogg');
    await Future<void>.delayed(Duration.zero);
    await player.dispose();
    engine.pendingLoad!.complete(const Duration(seconds: 20));
    await playing;
    expect(engine.calls, ['stop', 'load:/tmp/one.ogg', 'dispose']);
  });
}

// Only the native media engine is replaced; tests exercise our real adapter.
class _Engine implements native.AudioPlayer {
  final calls = <String>[];
  bool failLoad = false;
  Completer<Duration?>? pendingLoad;

  @override
  Duration? get duration => const Duration(seconds: 20);

  @override
  Future<Duration?> setFilePath(
    String filePath, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    calls.add('load:$filePath');
    if (failLoad) throw StateError('invalid audio');
    return pendingLoad == null ? duration : await pendingLoad!.future;
  }

  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> dispose() async => calls.add('dispose');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
