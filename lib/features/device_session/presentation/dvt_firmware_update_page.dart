import 'dart:async';

import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:aipin/core/design_system/widgets/app_surface_card.dart';
import 'package:aipin/features/device_session/application/wqota_update_controller.dart';
import 'package:aipin/features/device_session/domain/firmware_package.dart';
import 'package:flutter/material.dart';

class DvtFirmwareUpdatePage extends StatefulWidget {
  const DvtFirmwareUpdatePage({
    super.key,
    required this.deviceId,
    required this.loadPackage,
    required this.createController,
    required this.createVerificationController,
    required this.releaseTransport,
  });
  final String deviceId;
  final Future<FirmwarePackage> Function(String url) loadPackage;
  final Future<WqotaUpdateController> Function(FirmwarePackage)
  createController;
  final Future<WqotaUpdateController> Function(FirmwarePackage)
  createVerificationController;
  final Future<void> Function({WqotaUpdateController? owner}) releaseTransport;

  @override
  State<DvtFirmwareUpdatePage> createState() => _DvtFirmwareUpdatePageState();
}

class _DvtFirmwareUpdatePageState extends State<DvtFirmwareUpdatePage> {
  final _url = TextEditingController();
  WqotaUpdateController? _controller;
  FirmwarePackage? _package;
  bool _busy = false;
  bool _leaving = false;
  bool _canPop = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _controller?.removeListener(_changed);
    // Normal back goes through _leave; also cover external route removal.
    final controller = _controller;
    unawaited(() async {
      try {
        await controller?.cancel();
      } catch (_) {
        /* State/log contains failure. */
      }
      await widget.releaseTransport(owner: controller);
      controller?.dispose();
    }());
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _leave() async {
    if (_leaving || _canPop) return;
    if (mounted) {
      setState(() => _leaving = true);
    } else {
      _leaving = true;
    }
    final controller = _controller;
    try {
      await controller?.cancel();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      try {
        await widget.releaseTransport(owner: controller);
      } catch (error) {
        if (mounted) setState(() => _error = '$error');
      }
      // Keep PopScope closed until both cancellation and transport cleanup
      // finish; only then permit the programmatic route pop below.
      if (mounted) {
        setState(() {
          _busy = false;
          _canPop = true;
        });
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _package = null;
    });
    try {
      final package = await widget.loadPackage(_url.text.trim());
      if (mounted) setState(() => _package = package);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run({bool verifyOnly = false}) async {
    if (_busy || _package == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    WqotaUpdateController? acquiredController;
    try {
      final previous = _controller;
      previous?.removeListener(_changed);
      previous?.dispose();
      _controller = null;
      final controller = await (verifyOnly
          ? widget.createVerificationController
          : widget.createController)(_package!);
      acquiredController = controller;
      // A route remains mounted during its pop animation. A late CCC/setup
      // completion must release its own transport, not start an update after
      // the user has already left the page.
      if (!mounted || _leaving || _canPop) {
        await widget.releaseTransport(owner: controller);
        controller.dispose();
        return;
      }
      _controller = controller..addListener(_changed);
      if (verifyOnly) {
        // V1.6 post-reboot verification is a business 0x01 read. Do not
        // reopen 0x7033 just to inspect the saved checkpoint.
        await controller.resumeVerification(
          deviceId: widget.deviceId,
          package: _package!,
        );
      } else {
        await controller.start(deviceId: widget.deviceId, package: _package!);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      await widget.releaseTransport(owner: acquiredController);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final interactionBusy = _busy || _leaving;
    final state = _controller?.state;
    final phase = _leaving
        ? '正在停止任务并释放连接'
        : _busy && state == null
        ? (_package == null ? '正在读取并校验升级包' : '正在准备升级连接')
        : switch (state?.phase) {
            null || WqotaUpdatePhase.idle => '等待升级',
            WqotaUpdatePhase.preparing => '检查设备及镜像',
            WqotaUpdatePhase.transferring => '正在发送固件',
            WqotaUpdatePhase.verifying => '等待设备整镜像校验',
            WqotaUpdatePhase.awaitingReconnect => '已请求重启，请返回设备页重连并认证，再进入这里核验版本',
            WqotaUpdatePhase.completed => '升级完成，重连版本核验通过',
            WqotaUpdatePhase.cancelled => '升级已取消',
            WqotaUpdatePhase.failed => '升级未完成',
          };
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('DVT 固件升级')),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    '使用固件团队提供的 HTTPS 升级清单。清单须包含目标设备、镜像校验值、抓包确认的 WQOTA 帧头和最终校验支持声明。',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _url,
                    enabled: !interactionBusy,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: '升级清单 HTTPS 地址',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppButton.secondary(
                    label: '读取并校验升级包',
                    onPressed: interactionBusy
                        ? null
                        : () => unawaited(_load()),
                  ),
                  const SizedBox(height: 16),
                  if (_package case final package?)
                    AppSurfaceCard(
                      child: Text(
                        'VID：${package.vendorId} · PID：${package.productId}\n'
                        '目标版本：${package.expectedBusinessVersion}\n镜像：${package.payload.length} B\n'
                        '抓包依据：${package.wireFormat.captureId}',
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(phase),
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value:
                          state?.phase == WqotaUpdatePhase.transferring &&
                              state!.totalBytes > 0
                          ? (state.transferredBytes / state.totalBytes).clamp(
                              0.0,
                              1.0,
                            )
                          : null,
                    ),
                    if (state != null)
                      Text('${state.transferredBytes}/${state.totalBytes} B'),
                  ],
                  if (_error ?? state?.error case final error?)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: SelectableText(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  AppButton.primary(
                    label: '开始 / 恢复升级',
                    onPressed: interactionBusy || _package == null
                        ? null
                        : () => unawaited(_run()),
                  ),
                  const SizedBox(height: 8),
                  AppButton.secondary(
                    label: '重连后核验版本',
                    onPressed: interactionBusy || _package == null
                        ? null
                        : () => unawaited(_run(verifyOnly: true)),
                  ),
                  if (state?.isActive == true)
                    TextButton(
                      onPressed: () => unawaited(
                        _controller!.cancel().catchError((Object error) {
                          if (mounted) setState(() => _error = '$error');
                        }),
                      ),
                      child: const Text('取消升级'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
