import 'dart:io';
import 'dart:ui' as ui;

import 'package:aipin/core/design_system/evt_theme.dart';
import 'package:aipin/features/home/presentation/home_page.dart';
import 'package:aipin/features/device_session/application/session_state.dart';
import 'package:aipin/features/device_session/domain/device_auth_state.dart';
import 'package:aipin/features/device_session/domain/device_configuration.dart';
import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';
import 'package:aipin/features/device_session/domain/session_phase.dart';
import 'package:aipin/features/device_session/presentation/device_detail_page.dart';
import 'package:aipin/features/device_session/presentation/device_file_browser_page.dart';
import 'package:aipin/features/device_session/presentation/evt_security_code_sheet.dart';
import 'package:aipin/features/local_recording/presentation/audio_playback_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_audio_player.dart';

void main() {
  final fontPath = Platform.environment['EVT_REVIEW_FONT'];
  setUpAll(() async {
    if (fontPath != null) {
      final loader = FontLoader('ReviewFont')
        ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
  });
  final pages = <String, Widget Function()>{
    'home': () => HomePage(
      device: const DeviceSummary.connected(
        name: 'RECORD_0AA2',
        recordingLabel: '正在录音',
      ),
      onConnectDevice: () {},
      onOpenSettings: () {},
      onOpenDevice: () {},
      onOpenFiles: () {},
      onOpenSavedRecordings: () {},
      onOpenLogs: () {},
    ),
    'device': () => DeviceDetailPage(
      state: SessionState(
        phase: SessionPhase.observable,
        latestSnapshot: DeviceSnapshot(
          state: DeviceState.recording,
          observedAt: DateTime(2026, 9, 15, 15, 54),
          source: 'fixture',
        ),
        deviceBattery: const DeviceBattery(
          percent: 63,
          isCharging: false,
          chargingMode: 0,
        ),
        deviceStorage: const DeviceStorage(
          totalMegabytes: 211,
          freeMegabytes: 192,
        ),
        deviceStatus: const DeviceStatus(
          privacy: false,
          privacyRemainingMinutes: 0,
          recordConsent: true,
          syncState: 0,
        ),
        privacyDurationCode: 0,
        fileCount: 3,
      ),
      authState: DeviceAuthState.authenticated,
      canOpenFiles: true,
      canControlRecording: true,
      canConfigureDevice: true,
      canRefreshDeviceDetails: true,
      onRecordAction: (_) {},
      onRecordConsentChanged: (_) {},
      onOpenFiles: () {},
      onOpenLogs: () {},
      onOpenSavedRecordings: () {},
      onRefreshDeviceDetails: () {},
    ),
    'files': () => DeviceFileBrowserPage(
      onListFiles: ({required offset, required pageSize}) async => offset == 0
          ? const [
              DeviceFile(name: '06aa8f953.ogg', nameSlot: [1], length: 40387),
            ]
          : const [],
      onImport: (_, {onProgress}) => throw UnimplementedError(),
      onOpenSavedRecordings: () async {},
    ),
    'player': () => Scaffold(
      appBar: AppBar(title: const Text('06aa8f953.ogg')),
      body: AudioPlaybackPanel(
        duration: Duration.zero,
        resolvePath: () async => '/fixture.ogg',
        audioPlayerFactory: () =>
            FakeAudioPlayer()..playDuration = const Duration(seconds: 20),
        playbackErrorMessage: '无法播放',
      ),
    ),
    'security': () => const Scaffold(
      body: Center(
        child: EvtSecurityCodeSheet(
          title: '认证设备',
          message: '请输入该设备当前的安全码。',
          confirmLabel: '开始认证',
        ),
      ),
    ),
  };
  for (final scale in [1.0, 1.3]) {
    for (final page in pages.entries) {
      testWidgets('${page.key} fits a narrow screen at text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(scale == 1 ? 360 : 320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const key = ValueKey('review-screen');
        final theme = EvtTheme.light();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: fontPath == null
                  ? theme
                  : theme.copyWith(
                      textTheme: theme.textTheme.apply(
                        fontFamily: 'ReviewFont',
                      ),
                    ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: page.value(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (page.key == 'device') {
          expect(find.text('暂停录音').hitTestable(), findsOneWidget);
        }
        final directory = Platform.environment['EVT_REVIEW_OUTPUT'];
        if (directory != null && scale == 1) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(key),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(directory).create(recursive: true);
            await File(
              '$directory/${page.key}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
    }
  }
}
