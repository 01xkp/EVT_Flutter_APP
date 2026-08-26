import 'package:aipin/features/research_beta/domain/research_trial.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepting the trial preserves the anonymous participant identity', () {
    final trial = ResearchTrial.newParticipant(
      participantId: 'participant-1',
      startedAt: DateTime(2026, 8, 24),
    );

    final accepted = trial.accepted(DateTime(2026, 8, 25));

    expect(trial.hasAcceptedConsent, isFalse);
    expect(accepted.hasAcceptedConsent, isTrue);
    expect(accepted.participantId, 'participant-1');
    expect(accepted.startedAt, DateTime(2026, 8, 24));
  });

  test('daily prompt date is stored without card content', () {
    final trial = ResearchTrial.newParticipant(
      participantId: 'participant-1',
      startedAt: DateTime(2026, 8, 24),
    );

    final updated = trial.markDailyUnderstandingPrompted(
      DateTime(2026, 8, 24, 9),
    );

    expect(updated.lastDailyUnderstandingPromptOn, DateTime(2026, 8, 24));
  });
}
