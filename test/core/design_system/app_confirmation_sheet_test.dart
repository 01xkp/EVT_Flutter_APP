import 'package:evt_ble_app/core/design_system/widgets/app_confirmation_sheet.dart';
import 'package:evt_ble_app/core/design_system/widgets/permission_rationale_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('confirmation sheet returns false when cancelled', (
    tester,
  ) async {
    Future<bool>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () {
              result = AppConfirmationSheet.show(
                context,
                title: '删除录音？',
                message: '删除后将无法恢复。',
                confirmLabel: '删除',
              );
            },
            child: const Text('打开确认'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开确认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(await result, isFalse);
  });

  testWidgets('destructive confirmation returns true after confirmation', (
    tester,
  ) async {
    Future<bool>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () {
              result = AppConfirmationSheet.show(
                context,
                title: '删除录音？',
                message: '删除后将无法恢复。',
                confirmLabel: '删除',
                variant: AppConfirmationVariant.destructive,
              );
            },
            child: const Text('打开破坏性确认'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开破坏性确认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
  });

  testWidgets('permission rationale only continues after explicit consent', (
    tester,
  ) async {
    Future<bool>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () {
              result = PermissionRationaleSheet.show(
                context,
                title: '需要附近设备权限',
                message: '用于连接你的设备。',
              );
            },
            child: const Text('打开权限说明'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开权限说明'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
  });
}
