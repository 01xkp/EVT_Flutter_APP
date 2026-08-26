import 'package:aipin/features/local_recording/presentation/playback_waveform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses the page background instead of a card surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          scaffoldBackgroundColor: Colors.amber,
          colorScheme: const ColorScheme.light(surface: Colors.blue),
        ),
        home: const Scaffold(
          body: PlaybackWaveform(progress: 0.4, isPlaying: false),
        ),
      ),
    );

    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: find.byType(PlaybackWaveform),
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(decoration.color, Colors.amber);
    expect(decoration.border, isNull);
  });

  testWidgets('renders its animation without an embedded progress control', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PlaybackWaveform(progress: 0.4, isPlaying: true)),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(PlaybackWaveform),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is AnimatedBuilder &&
              widget.animation is AnimationController,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(PlaybackWaveform),
        matching: find.byType(Slider),
      ),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 240));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
  });
}
