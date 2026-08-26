import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:aipin/core/design_system/widgets/status_label.dart';
import 'package:aipin/core/protocol/device_event.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';
import 'package:aipin/features/evidence/domain/evidence_bundle.dart';
import 'package:aipin/features/evidence/domain/evidence_repository.dart';
import 'package:aipin/features/evidence/domain/evidence_source_records.dart';
import 'package:aipin/features/observation/domain/observation_run.dart';
import 'package:aipin/features/observation/domain/observation_scenario.dart';
import 'package:aipin/features/observation/domain/observation_verdict.dart';
import 'package:aipin/features/observation/domain/observation_verifier.dart';
import 'package:flutter/material.dart';

class ObservationPage extends StatefulWidget {
  const ObservationPage({
    super.key,
    required this.repository,
    required this.deviceId,
    required this.deviceName,
    required this.latestSnapshot,
    this.events = const [],
    this.initialScenario = ObservationScenario.deviceAccess,
    this.onRecordPhysicalFeedback,
    this.onSaved,
  });

  final EvidenceRepository repository;
  final String deviceId;
  final String deviceName;
  final DeviceSnapshot latestSnapshot;
  final List<DeviceEvent> events;
  final ObservationScenario initialScenario;
  final VoidCallback? onRecordPhysicalFeedback;
  final VoidCallback? onSaved;

  @override
  State<ObservationPage> createState() => _ObservationPageState();
}

class _ObservationPageState extends State<ObservationPage> {
  final _verifier = ObservationVerifier();
  late ObservationScenario _scenario;
  var _isSaving = false;
  var _isSaved = false;

  @override
  void initState() {
    super.initState();
    _scenario = widget.initialScenario;
  }

  @override
  Widget build(BuildContext context) {
    final result = _verifier.verify(_runFor(_scenario));
    final verdict = _statusFor(result.verdict);
    return Scaffold(
      appBar: AppBar(title: const Text('验证场景')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('选择场景', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final scenario in ObservationScenario.values)
                  ChoiceChip(
                    label: Text(scenario.title),
                    selected: _scenario == scenario,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _scenario = scenario;
                          _isSaved = false;
                        });
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              _scenario.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            StatusLabel(icon: verdict.$1, label: verdict.$2, kind: verdict.$3),
            const SizedBox(height: 8),
            Text(result.reason),
            const SizedBox(height: 16),
            Text('所需证据', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            for (final item in result.expectedEvidence) Text('- $item'),
            if (result.missingFields.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('缺失：${result.missingFields.join('、')}'),
            ],
            const SizedBox(height: 24),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _isSaved
                  ? const Padding(
                      key: ValueKey('saved'),
                      padding: EdgeInsets.only(bottom: 12),
                      child: StatusLabel(
                        icon: Icons.check_circle_outline,
                        label: '已保存',
                        kind: StatusKind.positive,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            if (_scenario == ObservationScenario.physicalFeedback)
              AppButton.primary(
                label: '记录人工观察',
                onPressed: widget.onRecordPhysicalFeedback,
                icon: Icons.edit_note_outlined,
              )
            else
              AppButton.primary(
                label: '保存验证结果',
                loading: _isSaving,
                onPressed: _isSaving || _isSaved ? null : _save,
                icon: Icons.save_outlined,
              ),
          ],
        ),
      ),
    );
  }

  ObservationRun _runFor(ObservationScenario scenario) {
    return ObservationRun(
      scenario: scenario,
      initialSnapshot: widget.latestSnapshot,
      finalSnapshot: widget.latestSnapshot,
      events: widget.events,
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final run = _runFor(_scenario);
    final result = _verifier.verify(run);
    try {
      await widget.repository.save(
        EvidenceBundle.completed(
          deviceId: widget.deviceId,
          deviceName: widget.deviceName,
          verdict: result.verdict,
          reason: result.reason,
          records: [
            EvidenceSourceRecords.snapshot(widget.latestSnapshot),
            for (final event in widget.events)
              EvidenceSourceRecords.event(event),
          ],
          diagnosticPayload: {
            'scenario': _scenario.name,
            'expectedEvidence': result.expectedEvidence,
            'missingFields': result.missingFields,
          },
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _isSaved = true;
      });
      widget.onSaved?.call();
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  (IconData, String, StatusKind) _statusFor(ObservationVerdict verdict) {
    return switch (verdict) {
      ObservationVerdict.passed => (
        Icons.check_circle_outline,
        '通过',
        StatusKind.positive,
      ),
      ObservationVerdict.failed => (
        Icons.cancel_outlined,
        '失败',
        StatusKind.danger,
      ),
      ObservationVerdict.unverifiable => (
        Icons.help_outline,
        '不可验证',
        StatusKind.neutral,
      ),
    };
  }
}
