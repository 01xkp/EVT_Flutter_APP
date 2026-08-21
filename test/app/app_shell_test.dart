import 'package:evt_ble_app/app/evt_app.dart';
import 'package:evt_ble_app/app/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_onboarding_store.dart';

void main() {
  testWidgets('completed onboarding reveals consumer navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingStoreProvider.overrideWithValue(
            FakeOnboardingStore(completed: true),
          ),
        ],
        child: const EvtApp(),
      ),
    );
    await tester.pump();

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('录音'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
  });
}
