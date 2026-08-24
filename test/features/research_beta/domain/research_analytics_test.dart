import 'package:aipin/features/research_beta/domain/research_analytics.dart';
import 'package:aipin/features/research_beta/domain/research_capture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'capture handled event excludes captured content from its database map',
    () {
      final event = ResearchEvent.captureHandled(
        participantId: 'participant-1',
        captureId: 'capture-1',
        action: ResearchCardAction.copied,
        duration: const Duration(seconds: 19),
        occurredAt: DateTime(2026, 8, 24),
      );

      expect(
        event.toDatabaseMap().keys,
        isNot(
          containsAll(<String>[
            'audioPath',
            'transcript',
            'summary',
            'title',
            'tags',
            'copiedText',
          ]),
        ),
      );
      expect(event.toDatabaseMap()['durationBucket'], '11-30s');
    },
  );

  test('useful reuse count ignores a not useful response', () {
    final aggregate = ResearchAggregate.empty(
      participantId: 'participant-1',
      createdAt: DateTime(2026, 8, 24),
    );

    final updated = aggregate.recordAction(ResearchCardAction.notUseful);

    expect(updated.handledCount, 1);
    expect(updated.usefulReuseCount, 0);
  });
}
