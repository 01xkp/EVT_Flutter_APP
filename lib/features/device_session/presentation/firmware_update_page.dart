import 'dart:async';

import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:aipin/core/design_system/widgets/app_confirmation_sheet.dart';
import 'package:aipin/core/design_system/widgets/app_surface_card.dart';
import 'package:aipin/features/device_session/application/wqota_update_controller.dart';
import 'package:aipin/features/device_session/domain/firmware_package.dart';
import 'package:flutter/material.dart';

class FirmwareUpdatePage extends StatefulWidget {
  const FirmwareUpdatePage({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.loadPackage,
    required this.createUpdateController,
    required this.reconnectAndVerify,
    this.closeUpdateChannel,
  });

  final String deviceId;
  final String deviceName;
  final Future<FirmwarePackage> Function() loadPackage;
  final WqotaUpdateController Function(FirmwarePackage package)
  createUpdateController;
  final Future<void> Function(WqotaUpdateController controller)
  reconnectAndVerify;
  final Future<void> Function()? closeUpdateChannel;

  @override
  State<FirmwareUpdatePage> createState() => _FirmwareUpdatePageState();
}

class _FirmwareUpdatePageState extends State<FirmwareUpdatePage> {
  FirmwarePackage? _package;
  WqotaUpdateController? _controller;
  Object? _loadError;
  Object? _actionError;
  var _isLoadingPackage = true;
  var _isReconnecting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPackage());
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    final closeUpdateChannel = widget.closeUpdateChannel;
    if (closeUpdateChannel != null) {
      unawaited(closeUpdateChannel());
    }
    super.dispose();
  }

  Future<void> _loadPackage() async {
    setState(() {
      _isLoadingPackage = true;
      _loadError = null;
      _actionError = null;
    });
    try {
      final package = await widget.loadPackage();
      if (!mounted) {
        return;
      }
      setState(() => _package = package);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loadError = error);
    } finally {
      if (mounted) {
        setState(() => _isLoadingPackage = false);
      }
    }
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _start() async {
    final package = _package;
    if (package == null) {
      return;
    }
    final confirmed = await AppConfirmationSheet.show(
      context,
      title: '开始固件升级？',
      message: '升级期间请保持设备充电或电量充足，并不要离开蓝牙连接范围。',
      confirmLabel: '开始升级',
    );
    if (!confirmed || !mounted) {
      return;
    }
    final previous = _controller;
    if (previous != null) {
      previous.removeListener(_onControllerChanged);
      await widget.closeUpdateChannel?.call();
    }
    final controller = widget.createUpdateController(package);
    controller.addListener(_onControllerChanged);
    setState(() {
      _controller = controller;
      _actionError = null;
    });
    try {
      await controller.start(deviceId: widget.deviceId, package: package);
    } catch (_) {
      // The controller carries a recoverable phase and error for the page.
    }
  }

  Future<void> _cancel() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final confirmed = await AppConfirmationSheet.show(
      context,
      title: '取消固件升级？',
      message: '设备会退出升级模式。下次只能使用同一已校验固件包继续处理。',
      confirmLabel: '取消升级',
      variant: AppConfirmationVariant.destructive,
    );
    if (confirmed) {
      await controller.cancel();
    }
  }

  Future<void> _reconnectAndVerify() async {
    final controller = _controller;
    if (controller == null || _isReconnecting) {
      return;
    }
    setState(() {
      _isReconnecting = true;
      _actionError = null;
    });
    try {
      await widget.reconnectAndVerify(controller);
    } catch (error) {
      if (mounted) {
        setState(() => _actionError = error);
      }
    } finally {
      if (mounted) {
        setState(() => _isReconnecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller?.state;
    final blockBack =
        state?.phase == WqotaUpdatePhase.preparing ||
        state?.phase == WqotaUpdatePhase.transferring ||
        state?.phase == WqotaUpdatePhase.verifying ||
        state?.phase == WqotaUpdatePhase.awaitingReconnect;
    return PopScope(
      canPop: !blockBack,
      child: Scaffold(
        appBar: AppBar(title: const Text('固件升级')),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                widget.deviceName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              if (_isLoadingPackage)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_loadError case final error?)
                _PackageUnavailableCard(
                  error: error,
                  onRetry: () => unawaited(_loadPackage()),
                )
              else if (_package case final package?) ...[
                _PackageCard(package: package),
                const SizedBox(height: 16),
                if (state != null) _UpdateStatusCard(state: state),
                if (_actionError case final error?) ...[
                  if (state != null) const SizedBox(height: 16),
                  _ActionErrorCard(error: error),
                ],
                const SizedBox(height: 20),
                _buildAction(state),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAction(WqotaUpdateState? state) {
    switch (state?.phase) {
      case WqotaUpdatePhase.preparing:
      case WqotaUpdatePhase.transferring:
      case WqotaUpdatePhase.verifying:
        return AppButton.destructive(
          label: '取消升级',
          icon: Icons.cancel_outlined,
          onPressed: () => unawaited(_cancel()),
        );
      case WqotaUpdatePhase.awaitingReconnect:
        return AppButton.primary(
          label: '重连并核验',
          icon: Icons.bluetooth_searching_outlined,
          loading: _isReconnecting,
          onPressed: _isReconnecting
              ? null
              : () => unawaited(_reconnectAndVerify()),
        );
      case WqotaUpdatePhase.completed:
        return const _CompletedLabel();
      case WqotaUpdatePhase.idle:
      case WqotaUpdatePhase.cancelled:
      case WqotaUpdatePhase.failed:
      case null:
        return AppButton.primary(
          label: state == null || state.phase == WqotaUpdatePhase.idle
              ? '开始升级'
              : '重新升级',
          icon: Icons.system_update_alt_outlined,
          onPressed: () => unawaited(_start()),
        );
    }
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({required this.package});

  final FirmwarePackage package;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('待安装固件', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _UpdateRow(label: '升级后版本', value: package.expectedBusinessVersion),
          const Divider(height: 24),
          _UpdateRow(label: '镜像版本', value: package.version.toString()),
          const Divider(height: 24),
          _UpdateRow(
            label: '镜像大小',
            value: _formatBytes(package.payload.length),
          ),
        ],
      ),
    );
  }
}

class _UpdateStatusCard extends StatelessWidget {
  const _UpdateStatusCard({required this.state});

  final WqotaUpdateState state;

  @override
  Widget build(BuildContext context) {
    final progress = state.totalBytes == 0
        ? null
        : (state.transferredBytes / state.totalBytes).clamp(0.0, 1.0);
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('升级状态', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text(_phaseLabel(state.phase)),
          if (state.phase == WqotaUpdatePhase.transferring) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text(
              '${_formatBytes(state.transferredBytes)} / ${_formatBytes(state.totalBytes)}',
            ),
          ],
          if (state.error case final error?) ...[
            const SizedBox(height: 12),
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _PackageUnavailableCard extends StatelessWidget {
  const _PackageUnavailableCard({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('暂时无法获取固件', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('固件包服务未配置。需要 HTTPS 固件清单、受控下载地址和目标设备版本映射后才能升级。'),
          const SizedBox(height: 8),
          Text('$error', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          AppButton.secondary(
            label: '重新检查',
            icon: Icons.refresh_outlined,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _ActionErrorCard extends StatelessWidget {
  const _ActionErrorCard({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(child: Text('重连核验失败：$error'));
  }
}

class _CompletedLabel extends StatelessWidget {
  const _CompletedLabel();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check_circle_outline),
        SizedBox(width: 8),
        Text('升级完成'),
      ],
    );
  }
}

class _UpdateRow extends StatelessWidget {
  const _UpdateRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 16),
        Flexible(
          child: Text(value, overflow: TextOverflow.ellipsis, maxLines: 1),
        ),
      ],
    );
  }
}

String _phaseLabel(WqotaUpdatePhase phase) => switch (phase) {
  WqotaUpdatePhase.idle => '等待开始',
  WqotaUpdatePhase.preparing => '正在准备升级',
  WqotaUpdatePhase.transferring => '正在传输固件',
  WqotaUpdatePhase.verifying => '正在校验镜像',
  WqotaUpdatePhase.awaitingReconnect => '设备正在重启，等待重连核验',
  WqotaUpdatePhase.completed => '已完成版本核验',
  WqotaUpdatePhase.cancelled => '已取消升级',
  WqotaUpdatePhase.failed => '升级失败',
};

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
