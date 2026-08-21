import 'package:evt_ble_app/features/onboarding/domain/onboarding_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesOnboardingStore implements OnboardingStore {
  static const _key = 'consumer_onboarding_complete';

  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  @override
  Future<bool> isComplete() async =>
      (await _preferences).getBool(_key) ?? false;

  @override
  Future<void> markComplete() async {
    await (await _preferences).setBool(_key, true);
  }
}
