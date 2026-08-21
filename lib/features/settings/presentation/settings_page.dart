import 'dart:async';

import 'package:evt_ble_app/core/ble/device_profile.dart';
import 'package:evt_ble_app/core/design_system/widgets/status_label.dart';
import 'package:evt_ble_app/features/settings/application/theme_mode_controller.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.profile, this.themeController});

  final DeviceProfile profile;
  final ThemeModeController? themeController;

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
          Text('设备配置', style: Theme.of(context).textTheme.titleMedium),
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
          _ProfileRow(label: '名称前缀', value: profile.namePrefix),
          _ProfileRow(label: '厂商数据', value: profile.manufacturerPrefixHex),
          _ProfileRow(label: '广播服务', value: profile.serviceUuid),
          _ProfileRow(
            label: '状态服务',
            value: _displayValue(profile.gattServiceUuid),
          ),
          _ProfileRow(
            label: '读取特征',
            value: _displayValue(profile.readCharacteristicUuid),
          ),
          _ProfileRow(
            label: '订阅特征',
            value: _displayValue(profile.notifyCharacteristicUuid),
          ),
        ],
      ),
    );
  }

  static String _displayValue(String value) => value.isEmpty ? '未配置' : value;
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          SelectableText(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
