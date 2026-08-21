import 'package:evt_ble_app/app/evt_app.dart';
import 'package:evt_ble_app/app/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_onboarding_store.dart';

void main() {
  testWidgets('renders the consumer welcome choice', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingStoreProvider.overrideWithValue(FakeOnboardingStore()),
        ],
        child: const EvtApp(),
      ),
    );
    await tester.pump();

    expect(find.text('AIPIN'), findsOneWidget);
    expect(find.text('连接我的设备'), findsOneWidget);
  });
}
