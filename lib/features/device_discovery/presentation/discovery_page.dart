import 'dart:async';

import 'package:aipin/core/ble/bluetooth_enable_gateway.dart';
import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:aipin/core/design_system/widgets/app_confirmation_sheet.dart';
import 'package:aipin/core/design_system/widgets/app_toast.dart';
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
    this.onOpenSystemSettings,
    this.bluetoothEnableGateway = const PlatformBluetoothEnableGateway(),
    this.onStartScan,
    this.onStopScan,
  });

  final DiscoveryController? controller;
  final Future<bool> Function(DeviceCandidate candidate)? onConnect;
  final VoidCallback? onSettings;

  /// iOS cannot programmatically enable the Bluetooth adapter. The shell
  /// supplies the platform-supported App Settings handoff so a user can check
  /// the Bluetooth permission before returning to retry the scan.
  final Future<bool> Function()? onOpenSystemSettings;
  final BluetoothEnableGateway bluetoothEnableGateway;

  /// Lets the shell prepare an explicit reconnect cycle before a user-driven
  /// scan begins. The page still starts its [controller] afterward.
  final Future<void> Function()? onStartScan;

  /// Lets the shell cancel its matching reconnect cycle before this page stops
  /// the shared scanner.
  final Future<void> Function()? onStopScan;

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage>
    with WidgetsBindingObserver {
  late DiscoveryState _state =
      widget.controller?.state ?? const DiscoveryState();
  var _isBluetoothPromptVisible = false;
  var _retryScanWhenResumed = false;
  Future<void> _scanActionTail = Future<void>.value();
  Future<void>? _pendingStartScan;
  Future<void>? _pendingStopScan;
  var _stopScanCompleted = false;
  var _isDisposed = false;
  var _isConnecting = false;

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
    _isDisposed = true;
    unawaited(_stopScanning());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_retryScanWhenResumed) {
      return;
    }
    _retryScanWhenResumed = false;
    unawaited(_startScanning());
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
                        onPressed: () => unawaited(_stopScanning()),
                        icon: Icons.close,
                      )
                    else
                      AppButton.primary(
                        label: '查找附近设备',
                        onPressed: () => unawaited(_startScanning()),
                        icon: Icons.radar_outlined,
                      ),
                    const SizedBox(height: 16),
                    Expanded(child: _buildContent(context)),
                    const SizedBox(height: 16),
                    AppButton.primary(
                      label: _isConnecting ? '正在连接' : '连接设备',
                      onPressed: _state.connectEnabled && !_isConnecting
                          ? () => unawaited(_connectSelectedDevice())
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
        onRetry: () => unawaited(_startScanning()),
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
          selected: candidate.connectionId == _state.selected?.connectionId,
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
    final canOpenSystemSettings = widget.onOpenSystemSettings != null;
    final confirmed = await AppConfirmationSheet.show(
      context,
      title: canRequestEnable ? '蓝牙未开启？' : '请开启蓝牙',
      message: canRequestEnable
          ? '开启蓝牙后即可查找附近设备。'
          : 'iPhone 不允许 App 直接开启蓝牙。请在控制中心或系统设置中打开蓝牙后返回。',
      cancelLabel: '暂不',
      confirmLabel: canRequestEnable
          ? '开启蓝牙'
          : canOpenSystemSettings
          ? '打开设置'
          : '我已开启',
    );
    if (!mounted || !confirmed) {
      _isBluetoothPromptVisible = false;
      return;
    }
    if (!canRequestEnable) {
      _retryScanWhenResumed = true;
      _isBluetoothPromptVisible = false;
      final openSystemSettings = widget.onOpenSystemSettings;
      if (openSystemSettings != null) {
        await openSystemSettings();
      }
      return;
    }
    final result = await widget.bluetoothEnableGateway.requestEnable();
    if (mounted && result == BluetoothEnableResult.enabled) {
      await _startScanning();
    }
    _isBluetoothPromptVisible = false;
  }

  Future<void> _startScanning() {
    final pending = _pendingStartScan;
    if (pending != null) {
      return pending;
    }
    late final Future<void> action;
    action = _enqueueScanAction(() async {
      if (_isDisposed) {
        return;
      }
      _stopScanCompleted = false;
      await widget.onStartScan?.call();
      if (!_isDisposed && mounted) {
        widget.controller?.start();
      }
    });
    _pendingStartScan = action;
    action.then<void>(
      (_) => _clearPendingStart(action),
      onError: (_, _) => _clearPendingStart(action),
    );
    return action;
  }

  Future<void> _connectSelectedDevice() async {
    final candidate = _state.selected;
    final connect = widget.onConnect;
    if (candidate == null || connect == null || _isDisposed || _isConnecting) {
      return;
    }
    setState(() => _isConnecting = true);
    var connected = false;
    try {
      connected = await connect(candidate);
    } catch (_) {
      connected = false;
    }
    if (!mounted || _isDisposed) {
      return;
    }
    setState(() => _isConnecting = false);
    if (connected) {
      Navigator.of(context).pop(candidate);
      return;
    }
    AppToast.show(context, message: '连接失败，请确认设备状态后重试');
  }

  Future<void> _stopScanning() {
    if (_stopScanCompleted) {
      return Future<void>.value();
    }
    final pending = _pendingStopScan;
    if (pending != null) {
      return pending;
    }
    final onStopScan = widget.onStopScan;
    final controller = widget.controller;
    late final Future<void> action;
    action = _enqueueScanAction(() async {
      await onStopScan?.call();
      await controller?.stop();
      _stopScanCompleted = true;
    });
    _pendingStopScan = action;
    action.then<void>(
      (_) => _clearPendingStop(action),
      onError: (_, _) => _clearPendingStop(action),
    );
    return action;
  }

  Future<void> _enqueueScanAction(Future<void> Function() action) {
    final queued = _scanActionTail.then<void>((_) => action());
    _scanActionTail = queued.then<void>((_) {}).catchError((_) {});
    return queued;
  }

  void _clearPendingStart(Future<void> action) {
    if (identical(_pendingStartScan, action)) {
      _pendingStartScan = null;
    }
  }

  void _clearPendingStop(Future<void> action) {
    if (identical(_pendingStopScan, action)) {
      _pendingStopScan = null;
    }
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
