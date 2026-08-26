import 'package:aipin/features/research_beta/domain/audio_segmenter.dart';
import 'package:flutter/services.dart';

class AudioSegmentationException implements Exception {
  const AudioSegmentationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PlatformM4aAudioSegmenter implements AudioSegmenter {
  static const _channel = MethodChannel('com.aigutta.aipin/audio-segmentation');

  @override
  Future<List<AudioSegment>> splitM4a(AudioSegmentationRequest request) async {
    try {
      final rawSegments = await _channel
          .invokeListMethod<Object?>('splitM4a', <String, Object?>{
            'sourcePath': request.sourcePath,
            'outputPathPrefix': request.outputPathPrefix,
            'maximumSegmentMilliseconds':
                request.maximumSegmentDuration.inMilliseconds,
          });
      if (rawSegments == null || rawSegments.isEmpty) {
        throw const AudioSegmentationException('原生音频切分未返回有效分段。');
      }
      final segments = <AudioSegment>[];
      for (final rawSegment in rawSegments) {
        if (rawSegment is! Map) {
          throw const AudioSegmentationException('原生音频切分结果格式无效。');
        }
        final index = rawSegment['index'];
        final durationMilliseconds = rawSegment['durationMilliseconds'];
        if (index is! int ||
            durationMilliseconds is! int ||
            index < 0 ||
            durationMilliseconds <= 0) {
          throw const AudioSegmentationException('原生音频切分结果格式无效。');
        }
        segments.add(
          AudioSegment(
            index: index,
            duration: Duration(milliseconds: durationMilliseconds),
          ),
        );
      }
      segments.sort((left, right) => left.index.compareTo(right.index));
      for (var index = 0; index < segments.length; index += 1) {
        if (segments[index].index != index) {
          throw const AudioSegmentationException('原生音频切分结果缺少分段。');
        }
      }
      return List.unmodifiable(segments);
    } on PlatformException catch (error) {
      throw AudioSegmentationException(error.message ?? '原生音频切分失败，请重新转写。');
    } on MissingPluginException {
      throw const AudioSegmentationException('当前平台不支持音频切分。');
    }
  }
}
