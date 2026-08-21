import 'dart:async';

import 'package:evt_ble_app/app/providers.dart';
import 'package:evt_ble_app/core/ble/device_profile_loader.dart';
import 'package:evt_ble_app/core/protocol/evt_protocol_codec.dart';
import 'package:evt_ble_app/features/device_discovery/application/discovery_controller.dart';
import 'package:evt_ble_app/features/device_discovery/domain/advertisement_filter.dart';
import 'package:evt_ble_app/features/device_discovery/domain/device_candidate.dart';
import 'package:evt_ble_app/features/device_discovery/presentation/discovery_page.dart';
import 'package:evt_ble_app/features/device_session/application/session_controller.dart';
import 'package:evt_ble_app/features/device_session/presentation/session_dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late final DiscoveryController _discoveryController;
  SessionController? _sessionController;
  var _destination = 0;

  @override
  void initState() {
    super.initState();
    _discoveryController = DiscoveryController(
      ref.read(bleTransportProvider),
      const AdvertisementFilter(),
    );
  }

  @override
  void dispose() {
    _discoveryController.dispose();
    _sessionController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _sessionController;
    final canRecord = session?.state.isObservable ?? false;
    return Scaffold(
      body: switch (_destination) {
        0 => session == null
            ? DiscoveryPage(
                controller: _discoveryController,
                onConnect: _openSession,
              )
            : AnimatedBuilder(
                animation: session,
                builder: (context, _) => SessionDashboardPage(state: session.state),
              ),
        1 => const _EvidencePlaceholder(),
        _ => const SizedBox.shrink(),
      },
      bottomNavigationBar: BottomAppBar(
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                tooltip: '设备联调',
                onPressed: () => setState(() => _destination = 0),
                icon: const Icon(Icons.bluetooth_searching_outlined),
              ),
              IconButton(
                tooltip: '记录观察',
                onPressed: canRecord ? _showObservationUnavailable : null,
                icon: const Icon(Icons.edit_note_outlined),
              ),
              IconButton(
                tooltip: '查看证据',
                onPressed: () => setState(() => _destination = 1),
                icon: const Icon(Icons.fact_check_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSession(DeviceCandidate candidate) async {
    try {
      await _discoveryController.stop();
      final profile = await const DeviceProfileLoader().load(rootBundle);
      if (!mounted) {
        return;
      }
      _sessionController?.dispose();
      final controller = SessionController(
        ref.read(bleTransportProvider),
        profile,
        EvtProtocolCodec(),
      );
      setState(() {
        _sessionController = controller;
        _destination = 0;
      });
      await controller.connect(candidate);
    } catch (_) {
      if (mounted) {
        setState(() => _sessionController = null);
      }
    }
  }

  void _showObservationUnavailable() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('观察记录将在验证场景开始后保存。'),
        ),
      ),
    );
  }
}

class _EvidencePlaceholder extends StatelessWidget {
  const _EvidencePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('证据记录')),
      body: const Center(child: Text('尚无已保存的观察记录')),
    );
  }
}
