import 'package:aipin/app/app_destination.dart';
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
