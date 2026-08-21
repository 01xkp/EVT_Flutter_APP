import 'package:evt_ble_app/app/evt_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the EVT workbench shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: EvtApp()));

    expect(find.text('设备联调'), findsOneWidget);
  });
}
