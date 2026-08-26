import 'package:aipin/core/design_system/widgets/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('toast is displayed at the center of the current page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => AppToast.show(
                context,
                message: '录音已保存到记录',
                duration: const Duration(minutes: 1),
              ),
              child: const Text('显示提示'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('显示提示'));
    await tester.pump();

    final toastCenter = tester.widget<Center>(
      find
          .ancestor(of: find.text('录音已保存到记录'), matching: find.byType(Center))
          .first,
    );
    expect(toastCenter.alignment, Alignment.center);
  });
}
