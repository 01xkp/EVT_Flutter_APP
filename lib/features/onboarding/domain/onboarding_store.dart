abstract interface class OnboardingStore {
  Future<bool> isComplete();

  Future<void> markComplete();
}
