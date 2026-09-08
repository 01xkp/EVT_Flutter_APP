import 'package:aipin/features/onboarding/presentation/welcome_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('welcome begins the EVT device connection flow', (tester) async {
    var connectCalls = 0;
    await tester.pumpWidget(
      MaterialApp(home: WelcomePage(onConnectDevice: () => connectCalls += 1)),
    );

    await tester.tap(find.text('连接我的设备'));

    expect(connectCalls, 1);
    expect(find.text('先用本机录音'), findsNothing);
  });
}
