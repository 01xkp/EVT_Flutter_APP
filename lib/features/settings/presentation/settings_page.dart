import 'dart:async';

import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/core/design_system/widgets/permission_rationale_sheet.dart';
import 'package:aipin/core/design_system/widgets/status_label.dart';
import 'package:aipin/core/permissions/app_permission_gateway.dart';
import 'package:aipin/features/settings/application/theme_mode_controller.dart';
import 'package:aipin/features/research_beta/application/research_capture_processing_controller.dart';
import 'package:aipin/core/design_system/widgets/app_dialog.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.profile,
    this.themeController,
    this.permissions,
    this.researchProcessing,
  });

  final DeviceProfile profile;
  final ThemeModeController? themeController;
  final AppPermissionGateway? permissions;
  final ResearchCaptureProcessingController? researchProcessing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (themeController case final controller?) ...[
            Text('显示', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) => SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                  ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                ],
                selected: {controller.mode},
                onSelectionChanged: (selection) =>
                    unawaited(controller.set(selection.first)),
              ),
            ),
            const SizedBox(height: 28),
          ],
          Text('权限', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (permissions case final gateway?)
            _PermissionRow(
              title: '附近设备',
              load: gateway.nearbyDevices,
              onOpenSettings: gateway.openSettings,
            )
          else
            const _StaticRow(label: '附近设备', value: '未检查'),
          const SizedBox(height: 12),
          if (permissions case final gateway?)
            _PermissionRow(
              title: '麦克风',
              load: gateway.microphone,
              onOpenSettings: gateway.openSettings,
            )
          else
            const _StaticRow(label: '麦克风', value: '未检查'),
          const SizedBox(height: 28),
          Text('设备', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          StatusLabel(
            icon: profile.isGattReady
                ? Icons.check_circle_outline
                : Icons.error_outline,
            label: profile.isGattReady ? 'GATT 配置已就绪' : 'GATT 配置未完成',
            kind: profile.isGattReady ? StatusKind.positive : StatusKind.danger,
          ),
          const SizedBox(height: 12),
          Text(
            profile.isGattReady ? '扫描、连接与状态验证可以开始。' : '扫描规则可用，连接验证已阻止',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          if (researchProcessing case final processing?) ...[
            const SizedBox(height: 28),
            Text('研究数据', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _deleteResearchData(context, processing),
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除全部研究数据'),
            ),
          ],
          const SizedBox(height: 28),
          Text('关于', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          const _StaticRow(label: '应用', value: 'AIPIN'),
        ],
      ),
    );
  }

  Future<void> _deleteResearchData(
    BuildContext context,
    ResearchCaptureProcessingController processing,
  ) async {
    final approved = await AppDialog.confirmDestructive(
      context,
      title: '删除全部研究数据？',
      message: '将删除研究音频副本、转写和卡片，不会删除本机录音。',
      confirmLabel: '删除',
    );
    if (approved) {
      await processing.deleteAllResearchData();
    }
  }
}

class _PermissionRow extends StatefulWidget {
  const _PermissionRow({
    required this.title,
    required this.load,
    required this.onOpenSettings,
  });

  final String title;
  final Future<AppPermissionState> Function() load;
  final Future<bool> Function() onOpenSettings;

  @override
  State<_PermissionRow> createState() => _PermissionRowState();
}

class _PermissionRowState extends State<_PermissionRow> {
  AppPermissionState? _state;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _PermissionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.load != widget.load) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final label = _state == AppPermissionState.granted ? '已开启' : '需要开启';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(widget.title),
      trailing: Text(label),
      onTap: _state == AppPermissionState.granted ? null : _recover,
    );
  }

  Future<void> _load() async {
    final state = await widget.load();
    if (mounted) setState(() => _state = state);
  }

  Future<void> _recover() async {
    final approved = await PermissionRationaleSheet.show(
      context,
      title: '需要${widget.title}权限',
      message: '请在系统设置中开启后再返回应用。',
      continueLabel: '前往系统设置',
    );
    if (approved) await widget.onOpenSettings();
  }
}

class _StaticRow extends StatelessWidget {
  const _StaticRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: Text(value),
  );
}
