import 'dart:async';
import 'dart:typed_data';

import 'package:aipin/features/device_session/application/dvt_audio_probe_controller.dart';
import 'package:aipin/features/device_session/presentation/dvt_audio_probe_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows observable DVT audio metrics and stops the probe', (
    tester,
  ) async {
    final payloads = StreamController<Uint8List>(sync: true);
    var startCount = 0;
    var stopCount = 0;
    final controller = DvtAudioProbeController(
      validatedAudioPayloads: payloads.stream,
      startDvtAudioProbe: () async => startCount += 1,
      stopDvtAudioProbe: () async => stopCount += 1,
    );
    addTearDown(() async {
      controller.dispose();
      await payloads.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DvtAudioProbePage(
          controller: controller,
          disposeController: false,
        ),
      ),
    );

    expect(find.text('帧数'), findsOneWidget);
    expect(find.text('接收字节'), findsOneWidget);
    expect(find.text('吞吐'), findsOneWidget);
    expect(
      find.text(DvtAudioProbeState.packetLossUnavailableMessage),
      findsOneWidget,
    );

    await tester.tap(find.text('开始验证'));
    await tester.pump();

    expect(startCount, 1);
    expect(find.text('正在接收'), findsOneWidget);
    payloads.add(Uint8List.fromList(const [1, 2, 3]));
    await tester.pump();
    expect(controller.state.frameCount, 1);
    expect(controller.state.byteCount, 3);

    await tester.tap(find.text('停止验证'));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();

    expect(stopCount, 1);
    expect(controller.state.phase, DvtAudioProbePhase.completed);
    expect(find.text('已停止'), findsOneWidget);
  });
}
