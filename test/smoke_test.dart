import 'package:aipin/app/evt_app.dart';
import 'package:aipin/app/providers.dart';
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

    expect(find.text('AIPIN 声存'), findsOneWidget);
    expect(find.text('连接我的设备'), findsOneWidget);
  });
}
