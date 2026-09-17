import 'package:aipin/features/device_session/data/shared_preferences_unbind_recovery_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'restores pending identities across store recreation and clears in order',
    () async {
      final store = SharedPreferencesUnbindRecoveryStore();
      await store.setPending(['physical:AA', 'connection:ios-uuid'], true);
      final restarted = SharedPreferencesUnbindRecoveryStore();
      expect(await restarted.containsAny(['connection:ios-uuid']), isTrue);
      expect(await restarted.containsAny(['physical:BB']), isFalse);
      final set = restarted.setPending(['physical:BB'], true);
      final clear = restarted.setPending([
        'physical:AA',
        'connection:ios-uuid',
      ], false);
      await Future.wait([set, clear]);
      expect(await restarted.containsAny(['physical:AA']), isFalse);
      expect(await restarted.containsAny(['physical:BB']), isTrue);
    },
  );
}
