class ResearchProcessingPollSchedule {
  const ResearchProcessingPollSchedule();

  static const _fastPollingUntil = Duration(minutes: 1);
  static const _mediumPollingUntil = Duration(minutes: 5);

  Duration nextDelay(Duration elapsed) {
    if (elapsed < _fastPollingUntil) {
      return const Duration(seconds: 2);
    }
    if (elapsed < _mediumPollingUntil) {
      return const Duration(seconds: 5);
    }
    return const Duration(seconds: 10);
  }
}
