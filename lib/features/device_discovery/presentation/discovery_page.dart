import 'dart:async';

import 'package:aipin/core/ble/bluetooth_enable_gateway.dart';
import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:aipin/core/design_system/widgets/app_confirmation_sheet.dart';
import 'package:aipin/core/design_system/widgets/status_label.dart';
import 'package:aipin/features/device_discovery/application/discovery_controller.dart';
import 'package:aipin/features/device_discovery/application/discovery_state.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';
import 'package:aipin/features/device_discovery/presentation/device_candidate_row.dart';
import 'package:aipin/features/device_discovery/presentation/discovery_scanning_indicator.dart';
import 'package:flutter/material.dart';

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({
    super.key,
    this.controller,
    this.onConnect,
    this.onSettings,
    this.bluetoothEnableGateway = const PlatformBluetoothEnableGateway(),
    this.onOpenBluetoothSettings,
  });

  final DiscoveryController? controller;
  final ValueChanged<DeviceCandidate>? onConnect;
  final VoidCallback? onSettings;
  final BluetoothEnableGateway bluetoothEnableGateway;
  final Future<void> Function()? onOpenBluetoothSettings;

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage>
    with WidgetsBindingObserver {
  late DiscoveryState _state =
      widget.controller?.state ?? const DiscoveryState();
  var _isBluetoothPromptVisible = false;
  var _retryScanWhenResumed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller?.addListener(_onStateChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_showBluetoothPromptIfNeeded()),
    );
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
    WidgetsBinding.instance.removeObserver(this);
    widget.controller?.removeListener(_onStateChanged);
    unawaited(widget.controller?.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_retryScanWhenResumed) {
      return;
    }
    _retryScanWhenResumed = false;
    widget.controller?.start();
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
      );
    }
    if (_state.isScanning && _state.candidates.isEmpty) {
      return const Center(child: DiscoveryScanningIndicator());
    }
    if (_state.candidates.isEmpty) {
      return const _DiscoveryEmptyState();
    }
    return ListView.builder(
      itemCount: _state.candidates.length,
      itemBuilder: (context, index) {
        final candidate = _state.candidates[index];
        return DeviceCandidateRow(
          candidate: candidate,
          selected: candidate.id == _state.selected?.id,
          onTap: () => widget.controller?.select(candidate),
        );
      },
    );
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() => _state = widget.controller!.state);
      unawaited(_showBluetoothPromptIfNeeded());
    }
  }

  Future<void> _showBluetoothPromptIfNeeded() async {
    if (!mounted || !_state.isBluetoothOff || _isBluetoothPromptVisible) {
      return;
    }
    _isBluetoothPromptVisible = true;
    final canRequestEnable = widget.bluetoothEnableGateway.canRequestEnable;
    final confirmed = await AppConfirmationSheet.show(
      context,
      title: canRequestEnable ? '蓝牙未开启？' : '请开启蓝牙',
      message: canRequestEnable
          ? '开启蓝牙后即可查找附近设备。'
          : '请在控制中心开启蓝牙后，返回 App 重新查找设备。',
      cancelLabel: '暂不',
      confirmLabel: canRequestEnable ? '开启蓝牙' : '打开应用设置',
    );
    if (!mounted || !confirmed) {
      _isBluetoothPromptVisible = false;
      return;
    }
    if (!canRequestEnable) {
      _retryScanWhenResumed = true;
      await widget.onOpenBluetoothSettings?.call();
      _isBluetoothPromptVisible = false;
      return;
    }
    final result = await widget.bluetoothEnableGateway.requestEnable();
    if (mounted && result == BluetoothEnableResult.enabled) {
      widget.controller?.start();
    }
    _isBluetoothPromptVisible = false;
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
  const _DiscoveryFailure({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

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
        ],
      ),
    );
  }
}
