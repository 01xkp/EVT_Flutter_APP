import 'dart:async';

import 'package:evt_ble_app/app/providers.dart';
import 'package:evt_ble_app/core/ble/device_profile_loader.dart';
import 'package:evt_ble_app/core/protocol/evt_protocol_codec.dart';
import 'package:evt_ble_app/features/device_discovery/application/discovery_controller.dart';
import 'package:evt_ble_app/features/device_discovery/domain/advertisement_filter.dart';
import 'package:evt_ble_app/features/device_discovery/domain/device_candidate.dart';
import 'package:evt_ble_app/features/device_discovery/presentation/discovery_page.dart';
import 'package:evt_ble_app/features/device_session/application/session_controller.dart';
import 'package:evt_ble_app/features/device_session/application/session_state.dart';
import 'package:evt_ble_app/features/device_session/presentation/session_dashboard_page.dart';
import 'package:evt_ble_app/features/evidence/application/evidence_history_controller.dart';
import 'package:evt_ble_app/features/evidence/presentation/evidence_history_page.dart';
import 'package:evt_ble_app/features/evidence/presentation/record_observation_sheet.dart';
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
  EvidenceHistoryController? _evidenceHistoryController;
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
    _evidenceHistoryController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _sessionController;
    return AnimatedBuilder(
      animation: session ?? _discoveryController,
      builder: (context, _) {
        final canRecord = session?.state.isObservable ?? false;
        return Scaffold(
          body: switch (_destination) {
            0 =>
              session == null
                  ? DiscoveryPage(
                      controller: _discoveryController,
                      onConnect: _openSession,
                    )
                  : SessionDashboardPage(
                      state: session.state,
                      onStartObservation: () =>
                          _showRecordObservation(session.state),
                      onRetry: () => _retrySession(session),
                    ),
            1 =>
              _evidenceHistoryController == null
                  ? const SizedBox.shrink()
                  : EvidenceHistoryPage(
                      controller: _evidenceHistoryController!,
                    ),
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
                    onPressed: canRecord
                        ? () => _showRecordObservation(session!.state)
                        : null,
                    icon: const Icon(Icons.edit_note_outlined),
                  ),
                  IconButton(
                    tooltip: '查看证据',
                    onPressed: _openEvidenceHistory,
                    icon: const Icon(Icons.fact_check_outlined),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

  void _showRecordObservation(SessionState state) {
    final session = state.session;
    final snapshot = state.latestSnapshot;
    if (session == null || snapshot == null) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => RecordObservationSheet(
        repository: ref.read(evidenceRepositoryProvider),
        deviceId: session.candidate.id,
        deviceName: session.candidate.name,
        latestSnapshot: snapshot,
        events: state.events,
        onSaved: () {
          final controller = _evidenceHistoryController;
          if (controller != null) {
            unawaited(controller.load());
          }
        },
      ),
    );
  }

  void _openEvidenceHistory() {
    _evidenceHistoryController ??= EvidenceHistoryController(
      ref.read(evidenceRepositoryProvider),
    );
    unawaited(_evidenceHistoryController!.load());
    setState(() => _destination = 1);
  }

  void _retrySession(SessionController controller) {
    final candidate = controller.state.session?.candidate;
    if (candidate != null) {
      unawaited(controller.connect(candidate));
    }
  }
}
