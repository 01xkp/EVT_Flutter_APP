import 'package:aipin/core/design_system/evt_colors.dart';
import 'package:aipin/core/design_system/evt_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app chrome uses the canvas color in both theme modes', () {
    for (final theme in [EvtTheme.light(), EvtTheme.dark()]) {
      expect(theme.appBarTheme.backgroundColor, theme.scaffoldBackgroundColor);
      expect(
        theme.navigationBarTheme.backgroundColor,
        theme.scaffoldBackgroundColor,
      );
      expect(
        EvtTheme.systemUiOverlayStyle(theme).systemNavigationBarColor,
        theme.scaffoldBackgroundColor,
      );
    }

    expect(EvtTheme.light().scaffoldBackgroundColor, EvtLightColors.canvas);
    expect(EvtTheme.dark().scaffoldBackgroundColor, EvtDarkColors.canvas);
  });

  testWidgets('filled buttons retain a finite width inside a row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: EvtTheme.light(),
        home: Scaffold(
          body: Row(
            children: [FilledButton(onPressed: () {}, child: const Text('保存'))],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(FilledButton)).width.isFinite, isTrue);
  });
}
