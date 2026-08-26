class ResearchTrial {
  const ResearchTrial({
    required this.participantId,
    required this.startedAt,
    this.consentedAt,
    this.lastDailyUnderstandingPromptOn,
  });

  final String participantId;
  final DateTime startedAt;
  final DateTime? consentedAt;
  final DateTime? lastDailyUnderstandingPromptOn;

  bool get hasAcceptedConsent => consentedAt != null;

  factory ResearchTrial.newParticipant({
    required String participantId,
    required DateTime startedAt,
  }) {
    return ResearchTrial(participantId: participantId, startedAt: startedAt);
  }

  ResearchTrial accepted(DateTime consentedAt) {
    return ResearchTrial(
      participantId: participantId,
      startedAt: startedAt,
      consentedAt: consentedAt,
      lastDailyUnderstandingPromptOn: lastDailyUnderstandingPromptOn,
    );
  }

  ResearchTrial markDailyUnderstandingPrompted(DateTime time) {
    return ResearchTrial(
      participantId: participantId,
      startedAt: startedAt,
      consentedAt: consentedAt,
      lastDailyUnderstandingPromptOn: DateTime(time.year, time.month, time.day),
    );
  }
}

abstract interface class ResearchTrialStore {
  Future<ResearchTrial?> load();
  Future<void> save(ResearchTrial trial);
}
