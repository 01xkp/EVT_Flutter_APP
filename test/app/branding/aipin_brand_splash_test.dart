import 'package:aipin/app/branding/aipin_brand.dart';
import 'package:aipin/app/branding/aipin_brand_splash.dart';
import 'package:aipin/app/branding/aipin_voice_page_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('startup surface presents the AIPIN 声存 identity', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AipinBrandSplash()));

    expect(find.byKey(const ValueKey('aipinBrandSplash')), findsOneWidget);
    expect(find.text(AipinBrand.displayName), findsOneWidget);
    expect(find.text(AipinBrand.tagline), findsOneWidget);
    expect(find.byType(AipinVoicePageMark), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      AipinBrand.launchCanvas,
    );
  });
}
