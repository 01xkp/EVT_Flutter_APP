import 'package:aipin/features/device_session/domain/session_phase.dart';
import 'package:aipin/features/device_session/presentation/phase_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shows authentication-ready status before device authentication',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PhaseIndicator(phase: SessionPhase.authenticationReady),
          ),
        ),
      );

      expect(find.text('等待设备认证'), findsOneWidget);
    },
  );
}
