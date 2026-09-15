import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:aipin/features/device_session/domain/evt_legacy_security_gateway.dart';
import 'package:aipin/features/device_session/presentation/evt_security_code_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (input, expected) in <(String, List<int>)>[
    ('123456', [0x31, 0x32, 0x33, 0x34, 0x35, 0x36]),
    ('aZ9!b?', [0x61, 0x5A, 0x39, 0x21, 0x62, 0x3F]),
    ('abcdef', [0x61, 0x62, 0x63, 0x64, 0x65, 0x66]),
    ('7a31c85e92b4', [0x7A, 0x31, 0xC8, 0x5E, 0x92, 0xB4]),
    ('313233343536', [0x31, 0x32, 0x33, 0x34, 0x35, 0x36]),
  ]) {
    testWidgets('submits $input as six protocol bytes for every action', (
      tester,
    ) async {
      String? submitted;
      await _openSheet(tester, (value) => submitted = value);
      await tester.enterText(find.byType(TextField), input);
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, '确认'));
      await tester.pumpAndSettle();

      expect(submitted, isNotNull);
      for (final action in EvtLegacySecurityAction.values) {
        final request = EvtLegacySecurityRequest(
          action: action,
          securityCode: submitted!,
        );
        expect(request.content, [action.wireValue, ...expected]);
      }
    });
  }

  testWidgets('rejects invalid input without silently removing characters', (
    tester,
  ) async {
    String? submitted;
    await _openSheet(tester, (value) => submitted = value);
    for (final input in [
      '',
      '12345',
      '1234567',
      '12345中',
      '12 456',
      '12345678901G',
    ]) {
      await tester.enterText(find.byType(TextField), input);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        input,
      );
      expect(
        tester
            .widget<AppButton>(find.widgetWithText(AppButton, '确认'))
            .onPressed,
        isNull,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submitted, isNull);
      expect(find.byType(EvtSecurityCodeSheet), findsOneWidget);
    }
    await tester.tap(find.widgetWithText(AppButton, '取消'));
    await tester.pumpAndSettle();
  });
}

Future<void> _openSheet(
  WidgetTester tester,
  ValueChanged<String?> onSubmitted,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => onSubmitted(
              await EvtSecurityCodeSheet.show(
                context,
                title: '认证设备',
                message: '请输入安全码',
                confirmLabel: '确认',
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}
