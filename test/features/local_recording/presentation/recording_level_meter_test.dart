import 'package:aipin/features/local_recording/presentation/recording_level_meter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders a stable nine-bar meter for every recording flow', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RecordingLevelMeter(value: 0.5))),
    );

    expect(find.byType(AnimatedContainer), findsNWidgets(9));
  });
}
