import 'package:aipin/features/research_beta/data/platform_m4a_audio_segmenter.dart';
import 'package:aipin/features/research_beta/domain/audio_segmenter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aigutta.aipin/audio-segmentation');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps ordered independently playable M4A segment metadata', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'splitM4a');
          expect(call.arguments, <String, Object?>{
            'sourcePath': '/recordings/long.m4a',
            'outputPathPrefix': '/research/capture-1.segment-',
            'maximumSegmentMilliseconds': 300000,
          });
          return <Object?>[
            <String, Object?>{'index': 0, 'durationMilliseconds': 300000},
            <String, Object?>{'index': 1, 'durationMilliseconds': 1234},
          ];
        });
    final segmenter = PlatformM4aAudioSegmenter();

    final segments = await segmenter.splitM4a(
      const AudioSegmentationRequest(
        sourcePath: '/recordings/long.m4a',
        outputPathPrefix: '/research/capture-1.segment-',
        maximumSegmentDuration: Duration(minutes: 5),
      ),
    );

    expect(segments.map((segment) => segment.index), <int>[0, 1]);
    expect(segments.map((segment) => segment.duration), <Duration>[
      const Duration(minutes: 5),
      const Duration(milliseconds: 1234),
    ]);
  });

  test('rejects a native segment result with a missing index', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => <Object?>[
            <String, Object?>{'index': 0, 'durationMilliseconds': 300000},
            <String, Object?>{'index': 2, 'durationMilliseconds': 300000},
          ],
        );
    final segmenter = PlatformM4aAudioSegmenter();

    await expectLater(
      segmenter.splitM4a(
        const AudioSegmentationRequest(
          sourcePath: '/recordings/long.m4a',
          outputPathPrefix: '/research/capture-1.segment-',
          maximumSegmentDuration: Duration(minutes: 5),
        ),
      ),
      throwsA(isA<AudioSegmentationException>()),
    );
  });
}
