import 'dart:async';

import 'package:aipin/features/local_recording/application/recording_controller.dart';
import 'package:aipin/features/local_recording/domain/audio_recorder_port.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/presentation/active_recording_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_audio_recorder.dart';
import '../../../support/fake_local_recording_repository.dart';
import '../../../support/fake_recording_background_service.dart';
import '../../../support/fake_recording_file_store.dart';

void main() {
  testWidgets('ending a recording returns the saved recording to its caller', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final repository = FakeLocalRecordingRepository();
    final controller = RecordingController(
      repository: repository,
      recorder: FakeAudioRecorder()..permission = RecorderPermission.granted,
      files: FakeRecordingFileStore(),
      background: FakeRecordingBackgroundService(),
      idGenerator: () => 'recording-1',
    );
    addTearDown(controller.close);

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: SizedBox()),
      ),
    );
    final savedResult = navigatorKey.currentState!.push<LocalRecording?>(
      MaterialPageRoute(
        builder: (context) => ActiveRecordingPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('结束录音'));
    await tester.pumpAndSettle();

    final recording = await savedResult;
    expect(recording, isNotNull);
    expect(recording!.id, 'recording-1');
    expect(recording.status, LocalRecordingStatus.saved);
    expect(repository.values.single.status, LocalRecordingStatus.saved);
  });

  testWidgets(
    'active recording waits for its route entrance before starting native capture',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final recorder = FakeAudioRecorder()
        ..permission = RecorderPermission.granted;
      final controller = RecordingController(
        repository: FakeLocalRecordingRepository(),
        recorder: recorder,
        files: FakeRecordingFileStore(),
        background: FakeRecordingBackgroundService(),
        idGenerator: () => 'recording-1',
      );
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      unawaited(
        navigatorKey.currentState!.push<void>(
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 180),
            pageBuilder: (_, _, _) =>
                ActiveRecordingPage(controller: controller),
          ),
        ),
      );

      await tester.pump();
      final route = ModalRoute.of(
        tester.element(find.byType(ActiveRecordingPage, skipOffstage: false)),
      );
      expect(route?.animation?.status, AnimationStatus.forward);
      expect(recorder.operations, isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 180));
      await tester.pump();
      expect(recorder.operations, <String>['start']);

      await controller.discard();
    },
  );

  testWidgets('active recorder confirms before exiting without saving', (
    tester,
  ) async {
    final repository = FakeLocalRecordingRepository();
    final recorder = FakeAudioRecorder()
      ..permission = RecorderPermission.granted;
    final controller = RecordingController(
      repository: repository,
      recorder: recorder,
      files: FakeRecordingFileStore(),
      background: FakeRecordingBackgroundService(),
      idGenerator: () => 'recording-1',
    );
    addTearDown(controller.close);

    await tester.pumpWidget(
      MaterialApp(home: ActiveRecordingPage(controller: controller)),
    );
    await tester.pump();

    expect(find.text('00:00:00'), findsOneWidget);
    expect(find.byTooltip('暂停录音'), findsOneWidget);
    expect(find.byTooltip('结束录音'), findsOneWidget);
    expect(find.byTooltip('退出录音'), findsOneWidget);
    final pageBackground = Theme.of(
      tester.element(find.byType(ActiveRecordingPage)),
    ).scaffoldBackgroundColor;
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      pageBackground,
    );
    expect(
      tester.widget<AppBar>(find.byType(AppBar)).backgroundColor,
      pageBackground,
    );
    final matchingSystemBars = tester
        .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        )
        .where(
          (region) => region.value.systemNavigationBarColor == pageBackground,
        );
    expect(matchingSystemBars, hasLength(1));

    await tester.tap(find.byTooltip('退出录音'));
    await tester.pumpAndSettle();

    expect(find.text('退出录音？'), findsOneWidget);
    expect(find.text('确认退出'), findsOneWidget);
    expect(find.text('继续录音'), findsOneWidget);
    expect(recorder.operations, ['start']);
    expect(controller.state.phase, ActiveRecordingPhase.recording);

    await tester.tap(find.text('继续录音'));
    await tester.pumpAndSettle();

    expect(find.text('退出录音？'), findsNothing);
    expect(controller.state.phase, ActiveRecordingPhase.recording);

    await tester.tap(find.byTooltip('退出录音'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认退出'));
    await tester.pumpAndSettle();

    expect(recorder.operations, ['start', 'stop']);
    expect(repository.values, isEmpty);
    expect(controller.state.phase, ActiveRecordingPhase.idle);
  });
}
