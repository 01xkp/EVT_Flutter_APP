import 'package:aipin/app/app_destination.dart';
import 'package:aipin/core/design_system/evt_colors.dart';
import 'package:aipin/core/design_system/evt_theme.dart';
import 'package:aipin/core/design_system/widgets/app_navigation_bar.dart';
import 'package:aipin/core/design_system/widgets/app_surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('navigation has only EVT device destinations', (tester) async {
    var selected = AppDestination.home;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppNavigationBar(
            selected: selected,
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.tap(find.text('检查记录'));

    expect(selected, AppDestination.records);
    expect(AppDestination.values, const [
      AppDestination.home,
      AppDestination.records,
    ]);
  });

  testWidgets('selected tab uses a readable foreground in both theme modes', (
    tester,
  ) async {
    for (final theme in [EvtTheme.light(), EvtTheme.dark()]) {
      for (final selected in AppDestination.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Theme(
              data: theme,
              child: Scaffold(
                bottomNavigationBar: AppNavigationBar(
                  selected: selected,
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        );

        final selectedLabel = selected == AppDestination.home ? '首页' : '检查记录';
        final unselectedLabel = selected == AppDestination.home ? '检查记录' : '首页';
        final selectedButton = tester.widget<TextButton>(
          find.widgetWithText(TextButton, selectedLabel),
        );
        final unselectedButton = tester.widget<TextButton>(
          find.widgetWithText(TextButton, unselectedLabel),
        );
        final expectedForeground = theme.brightness == Brightness.light
            ? EvtLightColors.primaryText
            : EvtDarkColors.primaryText;
        final expectedBackground = theme.brightness == Brightness.light
            ? EvtLightColors.subtle
            : EvtDarkColors.subtle;

        expect(
          selectedButton.style?.foregroundColor?.resolve(<WidgetState>{}),
          expectedForeground,
        );
        expect(
          selectedButton.style?.backgroundColor?.resolve(<WidgetState>{}),
          expectedBackground,
        );
        expect(
          unselectedButton.style?.foregroundColor?.resolve(<WidgetState>{}),
          theme.colorScheme.secondary,
        );
      }
    }
  });

  testWidgets('surface card exposes an accessible tap target', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSurfaceCard(
            onTap: () => taps += 1,
            selected: true,
            child: const Text('设备状态'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('设备状态'));

    expect(taps, 1);
    expect(
      tester.getSize(find.byType(AppSurfaceCard)).height,
      greaterThanOrEqualTo(44),
    );
  });
}
