import 'dart:async';

import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:aipin/core/design_system/widgets/app_confirmation_sheet.dart';
import 'package:aipin/core/design_system/widgets/app_surface_card.dart';
import 'package:aipin/features/device_session/application/session_state.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';
import 'package:aipin/features/device_session/domain/device_auth_state.dart';
import 'package:aipin/features/device_session/domain/device_configuration.dart';
import 'package:aipin/features/device_session/domain/evt_legacy_security_gateway.dart';
import 'package:aipin/features/device_session/presentation/device_status_view_model.dart';
import 'package:aipin/features/device_session/presentation/session_failure_panel.dart';
import 'package:flutter/material.dart';
import 'package:aipin/core/design_system/widgets/app_text_action.dart';

class DeviceDetailPage extends StatelessWidget {
  const DeviceDetailPage({
    super.key,
    required this.state,
    this.onDisconnect,
    this.onRetry,
    this.onOpenChecking,
    this.onOpenLogs,
    this.onOpenFiles,
    this.onOpenSavedRecordings,
    this.onOpenDvtAudio,
    this.onOpenDvtOta,
    this.onRecordAction,
    this.onRefreshDeviceDetails,
    this.onRecordConsentChanged,
    this.onPrivacyDurationChanged,
    this.authState = DeviceAuthState.unknown,
    this.authenticatingAction,
    this.onAuthenticate,
    this.onBind,
    this.onUnbind,
    this.onUnbindRecovery,
    this.canOpenFiles = false,
    this.canControlRecording = false,
    this.canConfigureDevice = false,
    this.canRefreshDeviceDetails = false,
  });

  final SessionState state;
  final VoidCallback? onDisconnect;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenChecking;
  final VoidCallback? onOpenLogs;
  final VoidCallback? onOpenFiles;
  final VoidCallback? onOpenSavedRecordings;
  final VoidCallback? onOpenDvtAudio;
  final VoidCallback? onOpenDvtOta;
  final ValueChanged<int>? onRecordAction;
  final VoidCallback? onRefreshDeviceDetails;
  final ValueChanged<bool>? onRecordConsentChanged;
  final ValueChanged<int>? onPrivacyDurationChanged;
  final DeviceAuthState authState;
  final EvtLegacySecurityAction? authenticatingAction;
  final VoidCallback? onAuthenticate;
  final VoidCallback? onBind;
  final VoidCallback? onUnbind;
  final VoidCallback? onUnbindRecovery;
  final bool canOpenFiles;
  final bool canControlRecording;
  final bool canConfigureDevice;
  final bool canRefreshDeviceDetails;

  @override
  Widget build(BuildContext context) {
    final status = DeviceStatusViewModel.from(state);
    final deviceName = state.session?.candidate.name ?? '我的设备';
    final authentication = _AuthenticationPanel(
      state: authState,
      authenticatingAction: authenticatingAction,
      onAuthenticate: onAuthenticate,
      onBind: onBind,
      onUnbind: onUnbind,
      onUnbindRecovery: onUnbindRecovery,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('设备详情'),
        actions: [AppTextAction(label: '实时日志', onPressed: onOpenLogs)],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(deviceName, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                AppSurfaceCard(
                  child: Column(
                    children: [
                      _DetailRow(label: '连接状态', value: status.connectionLabel),
                      const SizedBox(height: 8),
                      _DetailRow(label: '设备录音状态', value: status.recordingLabel),
                      if (authState == DeviceAuthState.authenticated) ...[
                        const SizedBox(height: 8),
                        const _DetailRow(label: '安全码认证', value: '已认证'),
                      ],
                    ],
                  ),
                ),
                if (state.failure case final failure?) ...[
                  const SizedBox(height: 12),
                  SessionFailurePanel(
                    failure: failure,
                    lastSnapshot: state.latestSnapshot,
                    onRetry: onRetry,
                  ),
                ],
                if (state.isAuthenticationReady &&
                    authState != DeviceAuthState.authenticated) ...[
                  const SizedBox(height: 12),
                  authentication,
                ],
                if (state.isObservable) ...[
                  const SizedBox(height: 12),
                  _RecordingControls(
                    state: state,
                    onAction: onRecordAction,
                    onOpenFiles: onOpenFiles,
                    canOpenFiles: canOpenFiles,
                    canControlRecording: canControlRecording,
                    canConfigure: canConfigureDevice,
                    onRecordConsentChanged: onRecordConsentChanged,
                  ),
                ],
                if (onOpenSavedRecordings != null) ...[
                  const SizedBox(height: 8),
                  AppButton.secondary(
                    label: '已保存录音',
                    onPressed: onOpenSavedRecordings,
                  ),
                ],
                if (state.isObservable) ...[
                  const SizedBox(height: 12),
                  _DeviceStatusPanel(
                    state: state,
                    canConfigure: canConfigureDevice,
                    canRefresh: canRefreshDeviceDetails,
                    onRefresh: onRefreshDeviceDetails,
                    onPrivacyDurationChanged: onPrivacyDurationChanged,
                  ),
                ],
                if (state.deviceInfo case final info?) ...[
                  const SizedBox(height: 12),
                  AppSurfaceCard(
                    child: Column(
                      children: [
                        _DetailRow(label: '设备编号', value: info.deviceCode),
                        const SizedBox(height: 8),
                        _DetailRow(label: '固件版本', value: info.softwareVersion),
                        if (status.updatedAt case final time?) ...[
                          const SizedBox(height: 8),
                          _DetailRow(
                            label: '状态采样时间',
                            value:
                                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}',
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (state.isObservable) ...[
                  const SizedBox(height: 12),
                  AppSurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'DVT 专项验证',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        AppButton.secondary(
                          label: 'DVT 实时音频验证',
                          onPressed: onOpenDvtAudio,
                        ),
                        if (onOpenDvtAudio == null)
                          const Text('需设备提供 FA18，并满足传输容量要求。'),
                        const SizedBox(height: 8),
                        AppButton.secondary(
                          label: 'DVT 固件升级',
                          onPressed: onOpenDvtOta,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppButton.secondary(label: '设备检查', onPressed: onOpenChecking),
                  const Text('手动记录联调结果，可在首页的检查记录中查看。'),
                ],
                const SizedBox(height: 12),
                if (status.canReconnect)
                  AppButton.primary(label: '重新连接', onPressed: onRetry)
                else
                  AppButton.secondary(
                    label: '断开设备',
                    onPressed: onDisconnect == null
                        ? null
                        : () => _confirmDisconnect(context),
                  ),
                if (authState == DeviceAuthState.authenticated) ...[
                  const SizedBox(height: 12),
                  ExpansionTile(
                    title: const Text('设备管理'),
                    subtitle: const Text('解绑会清除设备数据'),
                    children: [authentication],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDisconnect(BuildContext context) async {
    final confirmed = await AppConfirmationSheet.show(
      context,
      title: '断开设备？',
      message: '断开后将无法查看设备当前状态。',
      confirmLabel: '断开设备',
    );
    if (confirmed) {
      onDisconnect?.call();
    }
  }
}

class _DeviceStatusPanel extends StatelessWidget {
  const _DeviceStatusPanel({
    required this.state,
    required this.canConfigure,
    required this.canRefresh,
    this.onRefresh,
    this.onPrivacyDurationChanged,
  });

  final SessionState state;
  final bool canConfigure;
  final bool canRefresh;
  final VoidCallback? onRefresh;
  final ValueChanged<int>? onPrivacyDurationChanged;

  @override
  Widget build(BuildContext context) {
    final battery = state.deviceBattery;
    final storage = state.deviceStorage;
    final status = state.deviceStatus;
    final privacyDuration = state.privacyDurationCode;
    final canEditPrivacy =
        canConfigure &&
        privacyDuration != null &&
        onPrivacyDurationChanged != null;
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '设备状态',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              AppTextAction(
                label: '刷新状态',
                tooltip: '刷新设备状态',
                onPressed: canRefresh ? onRefresh : null,
              ),
            ],
          ),
          _DetailRow(
            label: '电量',
            value: battery == null
                ? '暂未读取'
                : battery.isCharging
                ? '${battery.percent}%（充电中）'
                : '${battery.percent}%',
          ),
          const Divider(height: 24),
          _DetailRow(
            label: '存储空间',
            value: storage == null
                ? '暂未读取'
                : '剩余 ${storage.freeMegabytes} / ${storage.totalMegabytes} MB',
          ),
          const Divider(height: 24),
          _DetailRow(
            label: '文件数量（上次）',
            value: state.fileCount == null ? '暂未读取' : '${state.fileCount} 个文件',
          ),
          const Divider(height: 24),
          _DetailRow(label: '隐私状态', value: _privacyLabel(status)),
          const Divider(height: 24),
          _DetailRow(label: '同步状态', value: _syncLabel(status)),
          const Divider(height: 24),
          PopupMenuButton<int>(
            tooltip: '默认隐私时长',
            enabled: canEditPrivacy,
            initialValue: privacyDuration,
            onSelected: onPrivacyDurationChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 0, child: Text('手动退出')),
              PopupMenuItem(value: 1, child: Text('10 分钟')),
              PopupMenuItem(value: 2, child: Text('30 分钟')),
              PopupMenuItem(value: 3, child: Text('60 分钟')),
            ],
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('默认隐私时长'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_privacyDurationLabel(privacyDuration)),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more_outlined),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _privacyLabel(DeviceStatus? status) {
    if (status == null) {
      return '暂未读取';
    }
    if (!status.privacy) {
      return '隐私模式已关闭';
    }
    if (status.privacyRemainingMinutes == 0xFFFF) {
      return '隐私模式，手动退出';
    }
    return '隐私模式，剩余 ${status.privacyRemainingMinutes} 分钟';
  }

  static String _syncLabel(DeviceStatus? status) => switch (status?.syncState) {
    0 => '空闲',
    1 => '同步中',
    2 => '录音暂停同步',
    3 => '同步失败',
    _ => '暂未读取',
  };

  static String _privacyDurationLabel(int? value) => switch (value) {
    0 => '手动退出',
    1 => '10 分钟',
    2 => '30 分钟',
    3 => '60 分钟',
    _ => '暂未读取',
  };
}

class _RecordingControls extends StatelessWidget {
  const _RecordingControls({
    required this.state,
    this.onAction,
    this.onOpenFiles,
    required this.canOpenFiles,
    required this.canControlRecording,
    required this.canConfigure,
    this.onRecordConsentChanged,
  });

  final SessionState state;
  final ValueChanged<int>? onAction;
  final VoidCallback? onOpenFiles;
  final bool canOpenFiles;
  final bool canControlRecording;
  final bool canConfigure;
  final ValueChanged<bool>? onRecordConsentChanged;

  @override
  Widget build(BuildContext context) {
    final snapshot = state.latestSnapshot;
    final status = state.deviceStatus;
    final canEditConsent =
        canConfigure && status != null && !state.isRecordActionInFlight;
    final action = switch (snapshot?.state) {
      DeviceState.recording => (2, '暂停录音', Icons.pause_outlined),
      DeviceState.paused => (3, '继续录音', Icons.play_arrow_outlined),
      _ => (1, '开始录音', Icons.fiber_manual_record_outlined),
    };
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('设备录音', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('允许设备录音'),
            subtitle: Text(
              status == null
                  ? '暂未读取'
                  : status.recordConsent
                  ? '已允许'
                  : '已关闭，开启后才能开始录音',
            ),
            value: status?.recordConsent ?? false,
            onChanged: canEditConsent && onRecordConsentChanged != null
                ? onRecordConsentChanged
                : null,
          ),

          if (state.deviceStatus?.recordConsent == false)
            const Text('请先开启“允许设备录音”。'),
          if (state.deviceStatus?.privacy == true)
            const Text('设备处于隐私模式，请先在设备端退出。'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppButton.primary(
                  label: action.$2,

                  onPressed:
                      state.isRecordActionInFlight ||
                          !canControlRecording ||
                          (action.$1 != 2 &&
                              (state.deviceStatus?.recordConsent == false ||
                                  state.deviceStatus?.privacy == true)) ||
                          onAction == null
                      ? null
                      : () => onAction!(action.$1),
                ),
              ),
              if (snapshot?.state == DeviceState.recording ||
                  snapshot?.state == DeviceState.paused) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton.secondary(
                    label: '结束录音',

                    onPressed:
                        state.isRecordActionInFlight ||
                            !canControlRecording ||
                            onAction == null
                        ? null
                        : () => onAction!(0),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          AppButton.secondary(
            label: '设备录音文件',

            onPressed: canOpenFiles ? onOpenFiles : null,
          ),
          if (state.isRecordActionInFlight) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }
}

class _AuthenticationPanel extends StatelessWidget {
  const _AuthenticationPanel({
    required this.state,
    this.authenticatingAction,
    this.onAuthenticate,
    this.onBind,
    this.onUnbind,
    this.onUnbindRecovery,
  });

  final DeviceAuthState state;
  final EvtLegacySecurityAction? authenticatingAction;
  final VoidCallback? onAuthenticate;
  final VoidCallback? onBind;
  final VoidCallback? onUnbind;
  final VoidCallback? onUnbindRecovery;

  @override
  Widget build(BuildContext context) {
    final authenticated = state == DeviceAuthState.authenticated;
    final inFlight = state == DeviceAuthState.authenticating;
    final recoveryPending = state == DeviceAuthState.unbindPending;
    final inFlightLabel = switch (authenticatingAction) {
      EvtLegacySecurityAction.bind => '等待设备确认',
      EvtLegacySecurityAction.unbind => '正在解绑',
      _ => '正在认证',
    };
    final label = switch (state) {
      DeviceAuthState.authenticated => '已认证',
      DeviceAuthState.authenticating => inFlightLabel,
      DeviceAuthState.unbindPending => '等待解绑恢复',
      _ => '未认证',
    };
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('设备认证（DVT）', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          if (!authenticated && !inFlight && !recoveryPending)
            const Text('已绑定设备选择“认证设备”；新设备选择“首次绑定设备”。'),
          if (inFlight &&
              authenticatingAction == EvtLegacySecurityAction.bind) ...[
            const SizedBox(height: 8),
            Text(
              '请在 60 秒内短按设备按键确认。设备确认后，App 会自动完成当前连接认证。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (recoveryPending) ...[
            const SizedBox(height: 12),
            Text(
              '上一次解绑尚未确认完成。请重新连接后使用同一设备安全码恢复。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            AppButton.secondary(label: '恢复解绑', onPressed: onUnbindRecovery),
          ] else if (inFlight) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ] else if (!authenticated) ...[
            const SizedBox(height: 12),
            AppButton.secondary(
              label: inFlight ? inFlightLabel : '认证设备',

              onPressed: inFlight ? null : onAuthenticate,
            ),
            const SizedBox(height: 8),
            AppButton.secondary(
              label: inFlight ? inFlightLabel : '首次绑定设备',

              onPressed: inFlight ? null : onBind,
            ),
          ],
          if (authenticated) ...[
            const SizedBox(height: 12),
            AppButton.destructive(
              label: '解绑设备',

              onPressed: onUnbind == null
                  ? null
                  : () => unawaited(_confirmUnbind(context)),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmUnbind(BuildContext context) async {
    final confirmed = await AppConfirmationSheet.show(
      context,
      title: '解绑设备？',
      message: '解绑会清除设备上的录音、绑定凭证和用户配置，且无法恢复。请确认已完成设备文件归档。',
      confirmLabel: '继续解绑',
      variant: AppConfirmationVariant.destructive,
    );
    if (confirmed) {
      onUnbind?.call();
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      ],
    );
  }
}
