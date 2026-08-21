import 'dart:async';

import 'package:evt_ble_app/core/design_system/evt_theme.dart';
import 'package:evt_ble_app/core/design_system/widgets/app_button.dart';
import 'package:evt_ble_app/core/design_system/widgets/status_label.dart';
import 'package:evt_ble_app/features/device_discovery/application/discovery_controller.dart';
import 'package:evt_ble_app/features/device_discovery/application/discovery_state.dart';
import 'package:evt_ble_app/features/device_discovery/domain/device_candidate.dart';
import 'package:evt_ble_app/features/device_discovery/presentation/device_candidate_row.dart';
import 'package:flutter/material.dart';

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({
    super.key,
    this.controller,
    this.onConnect,
    this.onSettings,
    this.onConnectionHelp,
  });

  final DiscoveryController? controller;
  final ValueChanged<DeviceCandidate>? onConnect;
  final VoidCallback? onSettings;
  final VoidCallback? onConnectionHelp;

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage> {
  late DiscoveryState _state =
      widget.controller?.state ?? const DiscoveryState();

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onStateChanged);
  }

  @override
  void didUpdateWidget(covariant DiscoveryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller?.removeListener(_onStateChanged);
    widget.controller?.addListener(_onStateChanged);
    _state = widget.controller?.state ?? const DiscoveryState();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('连接设备'),
        actions: [
          IconButton(
            tooltip: '设置',
            onPressed: widget.onSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth > 600 ? 640 : double.infinity,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '查找附近设备',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _state.isScanning ? '正在查找附近设备' : '靠近设备后开始查找',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    if (_state.isScanning)
                      AppButton.secondary(
                        label: '停止查找',
                        onPressed: () => unawaited(widget.controller?.stop()),
                        icon: Icons.close,
                      )
                    else
                      AppButton.primary(
                        label: '查找附近设备',
                        onPressed: widget.controller?.start,
                        icon: Icons.radar_outlined,
                      ),
                    const SizedBox(height: 16),
                    Expanded(child: _buildContent(context)),
                    const SizedBox(height: 16),
                    AppButton.primary(
                      label: '连接设备',
                      onPressed: _state.connectEnabled
                          ? () => widget.onConnect?.call(_state.selected!)
                          : null,
                      icon: Icons.bluetooth_connected,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_state.failure case final failure?) {
      return _DiscoveryFailure(
        message: failure.message,
        onRetry: widget.controller?.start,
        onHelp: widget.onConnectionHelp ?? () => _showConnectionHelp(context),
      );
    }
    if (_state.candidates.isEmpty) {
      return const _DiscoveryEmptyState();
    }
    return AnimatedSwitcher(
      duration: EvtTheme.motionDuration,
      child: ListView.builder(
        key: ValueKey(_state.candidates.length),
        itemCount: _state.candidates.length,
        itemBuilder: (context, index) {
          final candidate = _state.candidates[index];
          return DeviceCandidateRow(
            candidate: candidate,
            selected: candidate.id == _state.selected?.id,
            onTap: () => widget.controller?.select(candidate),
          );
        },
      ),
    );
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() => _state = widget.controller!.state);
    }
  }

  void _showConnectionHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('连接帮助', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text('确认设备已开机，并尽量靠近手机后重新查找。'),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('知道了'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoveryEmptyState extends StatelessWidget {
  const _DiscoveryEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: StatusLabel(
        icon: Icons.radar_outlined,
        label: '尚未发现附近设备',
        kind: StatusKind.neutral,
      ),
    );
  }
}

class _DiscoveryFailure extends StatelessWidget {
  const _DiscoveryFailure({required this.message, this.onRetry, this.onHelp});

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusLabel(
            icon: Icons.bluetooth_disabled_outlined,
            label: message,
            kind: StatusKind.danger,
          ),
          const SizedBox(height: 12),
          AppButton.secondary(
            label: '重新查找',
            onPressed: onRetry,
            icon: Icons.refresh,
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onHelp, child: const Text('查看连接帮助')),
        ],
      ),
    );
  }
}
