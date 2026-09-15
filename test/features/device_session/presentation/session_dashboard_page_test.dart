import 'package:aipin/features/device_session/application/session_state.dart';
import 'package:aipin/features/device_session/domain/session_phase.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';
import 'package:aipin/features/device_session/domain/device_auth_state.dart';
import 'package:aipin/features/device_session/domain/device_configuration.dart';
import 'package:aipin/features/device_session/domain/evt_legacy_security_gateway.dart';
import 'package:aipin/features/device_session/presentation/device_detail_page.dart';
import 'package:aipin/features/device_session/presentation/session_dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aipin/core/design_system/widgets/app_button.dart';

void main() {
  testWidgets('dashboard keeps the compatibility route consumer-facing', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SessionDashboardPage()));

    expect(find.text('设备详情'), findsOneWidget);
    expect(find.text('暂时无法获取'), findsOneWidget);
    expect(find.text('重新连接'), findsOneWidget);
  });

  testWidgets('detail asks before disconnecting', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DeviceDetailPage(
          state: SessionState(phase: SessionPhase.observable),
          onDisconnect: _noOp,
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('断开设备'),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('断开设备'));
    await tester.pumpAndSettle();

    expect(find.text('断开设备？'), findsOneWidget);
  });

  testWidgets('detail exposes the realtime log viewer entry point', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceDetailPage(
          state: const SessionState(phase: SessionPhase.observable),
          onOpenLogs: () => opened = true,
        ),
      ),
    );

    await tester.tap(find.byTooltip('实时日志'));

    expect(opened, isTrue);
  });

  testWidgets(
    'detail exposes hardware recording controls for an active device',
    (tester) async {
      int? action;
      await tester.pumpWidget(
        MaterialApp(
          home: DeviceDetailPage(
            state: SessionState(
              phase: SessionPhase.observable,
              latestSnapshot: DeviceSnapshot(
                state: DeviceState.recording,
                observedAt: DateTime(2026, 8, 21),
                source: 'test',
              ),
            ),
            onRecordAction: (value) => action = value,
            canControlRecording: true,
          ),
        ),
      );

      await tester.scrollUntilVisible(
        find.text('暂停录音'),
        200,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('设备录音'), findsOneWidget);
      expect(find.text('暂停录音'), findsOneWidget);
      expect(find.text('结束录音'), findsOneWidget);
      final pauseRecording = find.text('暂停录音');
      await tester.drag(find.byType(Scrollable), const Offset(0, -160));
      await tester.pumpAndSettle();
      await tester.tap(pauseRecording);
      expect(action, 2);
    },
  );

  testWidgets('detail omits deferred DVT and PVT controls in EVT', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DeviceDetailPage(
          state: SessionState(phase: SessionPhase.observable),
        ),
      ),
    );

    expect(find.text('实时音频'), findsNothing);
    expect(find.text('固件升级'), findsNothing);
    expect(find.text('确认清除设备'), findsNothing);
  });

  testWidgets(
    'detail renders authoritative device status and configuration controls',
    (tester) async {
      bool? recordConsent;
      int? privacyDuration;
      await tester.pumpWidget(
        MaterialApp(
          home: DeviceDetailPage(
            state: const SessionState(
              phase: SessionPhase.observable,
              deviceBattery: DeviceBattery(
                percent: 80,
                isCharging: true,
                chargingMode: 0,
              ),
              deviceStorage: DeviceStorage(
                totalMegabytes: 256,
                freeMegabytes: 128,
              ),
              fileCount: 3,
              deviceStatus: DeviceStatus(
                privacy: true,
                privacyRemainingMinutes: 15,
                recordConsent: true,
                syncState: 0,
              ),
              privacyDurationCode: 2,
            ),
            canConfigureDevice: true,
            onRecordConsentChanged: (value) => recordConsent = value,
            onPrivacyDurationChanged: (value) => privacyDuration = value,
          ),
        ),
      );

      expect(find.text('设备状态'), findsOneWidget);
      expect(find.text('80%（充电中）'), findsOneWidget);
      expect(find.text('剩余 128 / 256 MB'), findsOneWidget);
      expect(find.text('3 个文件'), findsOneWidget);
      expect(find.text('隐私模式，剩余 15 分钟'), findsOneWidget);

      final consentSwitch = find.byType(Switch);
      await tester.scrollUntilVisible(
        consentSwitch,
        200,
        scrollable: find.byType(Scrollable),
      );
      await tester.drag(find.byType(Scrollable), const Offset(0, -240));
      await tester.pumpAndSettle();
      await tester.tap(consentSwitch);
      expect(recordConsent, isFalse);
      expect(privacyDuration, isNull);
    },
  );

  testWidgets(
    'detail disables protected status refresh without a status grant',
    (tester) async {
      var refreshCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DeviceDetailPage(
            state: const SessionState(phase: SessionPhase.observable),
            onRefreshDeviceDetails: () => refreshCount += 1,
          ),
        ),
      );

      final refreshButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.refresh_outlined),
          matching: find.byType(IconButton),
        ),
      );
      expect(refreshButton.onPressed, isNull);

      await tester.tap(find.byIcon(Icons.refresh_outlined));
      expect(refreshCount, 0);
    },
  );

  testWidgets(
    'detail exposes an explicit authentication command before file access',
    (tester) async {
      var requested = false;
      await tester.pumpWidget(
        MaterialApp(
          home: DeviceDetailPage(
            state: const SessionState(phase: SessionPhase.observable),
            authState: DeviceAuthState.unbound,
            onAuthenticate: () => requested = true,
          ),
        ),
      );

      await tester.scrollUntilVisible(
        find.text('设备认证（EVT）'),
        200,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('设备认证（EVT）'), findsOneWidget);
      await tester.tap(find.text('认证设备'));
      expect(requested, isTrue);
    },
  );

  testWidgets(
    'EVT unbind confirmation explains that device data is irrecoverable',
    (tester) async {
      var resetRequested = false;
      await tester.pumpWidget(
        MaterialApp(
          home: DeviceDetailPage(
            state: const SessionState(phase: SessionPhase.observable),
            authState: DeviceAuthState.authenticated,
            onUnbind: () => resetRequested = true,
          ),
        ),
      );

      await tester.scrollUntilVisible(
        find.text('解绑设备'),
        200,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.text('解绑设备'));
      await tester.pumpAndSettle();

      expect(
        find.text('解绑会清除设备上的录音、绑定凭证和用户配置，且无法恢复。请确认已完成文件同步。'),
        findsOneWidget,
      );

      await tester.tap(find.text('继续解绑'));
      expect(resetRequested, isTrue);
    },
  );

  testWidgets('EVT pending unbind exposes only the recovery action', (
    tester,
  ) async {
    var recoveryRequested = false;
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceDetailPage(
          state: const SessionState(phase: SessionPhase.authenticationReady),
          authState: DeviceAuthState.unbindPending,
          onUnbindRecovery: () => recoveryRequested = true,
          onAuthenticate: () {},
          onBind: () {},
          onUnbind: () {},
        ),
      ),
    );

    expect(find.text('等待解绑恢复'), findsOneWidget);
    expect(find.widgetWithText(AppButton, '恢复解绑'), findsOneWidget);
    expect(find.widgetWithText(AppButton, '认证设备'), findsNothing);
    expect(find.widgetWithText(AppButton, '首次绑定设备'), findsNothing);
    expect(find.widgetWithText(AppButton, '解绑设备'), findsNothing);

    await tester.tap(find.widgetWithText(AppButton, '恢复解绑'));
    expect(recoveryRequested, isTrue);
  });

  testWidgets(
    'EVT binding tells the user to confirm on the device before automatic AUTH',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DeviceDetailPage(
            state: SessionState(phase: SessionPhase.authenticationReady),
            authState: DeviceAuthState.authenticating,
            authenticatingAction: EvtLegacySecurityAction.bind,
          ),
        ),
      );

      expect(find.text('等待设备确认'), findsNWidgets(3));
      expect(
        find.text('请在 60 秒内短按设备按键确认。设备确认后，App 会自动完成当前连接认证。'),
        findsOneWidget,
      );
      expect(find.text('正在认证'), findsNothing);
    },
  );
}

void _noOp() {}
