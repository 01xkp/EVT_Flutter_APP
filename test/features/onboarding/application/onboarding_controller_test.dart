import 'package:aipin/features/onboarding/application/onboarding_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_onboarding_store.dart';

void main() {
  test('completion persists the welcome decision', () async {
    final store = FakeOnboardingStore();
    final controller = OnboardingController(store);
    addTearDown(controller.dispose);

    expect(await controller.load(), isFalse);

    await controller.complete();

    expect(store.completed, isTrue);
    expect(controller.isComplete, isTrue);
  });
}
