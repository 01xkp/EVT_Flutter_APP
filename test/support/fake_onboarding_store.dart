import 'package:evt_ble_app/features/onboarding/domain/onboarding_store.dart';

class FakeOnboardingStore implements OnboardingStore {
  FakeOnboardingStore({this.completed = false});

  bool completed;

  @override
  Future<bool> isComplete() async => completed;

  @override
  Future<void> markComplete() async {
    completed = true;
  }
}
