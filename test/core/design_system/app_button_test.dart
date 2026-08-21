import 'package:evt_ble_app/core/design_system/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('disabled primary button cannot invoke its command', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppButton.primary(label: '连接设备', onPressed: null),
        ),
      ),
    );

    await tester.tap(find.text('连接设备'));

    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });

  testWidgets('loading primary button blocks its command and presents progress', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppButton.primary(
            label: '连接设备',
            loading: true,
            onPressed: () => calls += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(FilledButton));

    expect(calls, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
