import 'package:aipin/features/research_beta/domain/research_capture.dart';

enum ResearchEventType {
  captureCreated,
  processingChanged,
  captureOpened,
  captureHandled,
  qualityFeedback,
  dailyUnderstanding,
  remoteDeleteFailed,
}

class ResearchEvent {
  const ResearchEvent({
    required this.id,
    required this.participantId,
    required this.captureId,
    required this.type,
    required this.occurredAt,
    this.processingState,
    this.durationBucket,
    this.action,
    this.qualityFeedback,
    this.dailyUnderstanding,
    this.elapsedMilliseconds,
  });

  final String id;
  final String participantId;
  final String captureId;
  final ResearchEventType type;
  final DateTime occurredAt;
  final ResearchProcessingState? processingState;
  final String? durationBucket;
  final ResearchCardAction? action;
  final bool? qualityFeedback;
  final bool? dailyUnderstanding;
  final int? elapsedMilliseconds;

  factory ResearchEvent.captureHandled({
    required String participantId,
    required String captureId,
    required ResearchCardAction action,
    required Duration duration,
    required DateTime occurredAt,
  }) {
    return ResearchEvent(
      id: '$captureId-${occurredAt.microsecondsSinceEpoch}-${action.name}',
      participantId: participantId,
      captureId: captureId,
      type: ResearchEventType.captureHandled,
      occurredAt: occurredAt,
      action: action,
      durationBucket: durationBucketFor(duration),
    );
  }

  static String durationBucketFor(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds <= 10) {
      return '2-10s';
    }
    if (seconds <= 30) {
      return '11-30s';
    }
    return '31-60s';
  }

  Map<String, Object?> toDatabaseMap() => <String, Object?>{
    'id': id,
    'participantId': participantId,
    'captureId': captureId,
    'type': type.name,
    'occurredAt': occurredAt.toIso8601String(),
    'processingState': processingState?.name,
    'durationBucket': durationBucket,
    'action': action?.name,
    'qualityFeedback': qualityFeedback,
    'dailyUnderstanding': dailyUnderstanding,
    'elapsedMilliseconds': elapsedMilliseconds,
  };
}

class ResearchAggregate {
  const ResearchAggregate({
    required this.participantId,
    required this.createdAt,
    required this.updatedAt,
    this.captureCount = 0,
    this.handledCount = 0,
    this.usefulReuseCount = 0,
    this.accurateFeedbackCount = 0,
    this.inaccurateFeedbackCount = 0,
    this.understoodCount = 0,
    this.notUnderstoodCount = 0,
  });

  final String participantId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int captureCount;
  final int handledCount;
  final int usefulReuseCount;
  final int accurateFeedbackCount;
  final int inaccurateFeedbackCount;
  final int understoodCount;
  final int notUnderstoodCount;

  factory ResearchAggregate.empty({
    required String participantId,
    required DateTime createdAt,
  }) {
    return ResearchAggregate(
      participantId: participantId,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  ResearchAggregate recordAction(ResearchCardAction action) {
    return ResearchAggregate(
      participantId: participantId,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      captureCount: captureCount,
      handledCount: handledCount + 1,
      usefulReuseCount:
          usefulReuseCount + (action == ResearchCardAction.notUseful ? 0 : 1),
      accurateFeedbackCount: accurateFeedbackCount,
      inaccurateFeedbackCount: inaccurateFeedbackCount,
      understoodCount: understoodCount,
      notUnderstoodCount: notUnderstoodCount,
    );
  }
}
