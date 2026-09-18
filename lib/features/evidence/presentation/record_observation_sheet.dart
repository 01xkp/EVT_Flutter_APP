import 'package:aipin/core/protocol/device_event.dart';
import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:aipin/core/design_system/widgets/app_toast.dart';
import 'package:aipin/core/design_system/widgets/status_label.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';
import 'package:aipin/features/evidence/domain/evidence_bundle.dart';
import 'package:aipin/features/evidence/domain/evidence_repository.dart';
import 'package:aipin/features/evidence/domain/evidence_source_records.dart';
import 'package:aipin/features/observation/domain/observation_run.dart';
import 'package:aipin/features/observation/domain/observation_scenario.dart';
import 'package:aipin/features/observation/domain/observation_verifier.dart';
import 'package:flutter/material.dart';

class RecordObservationSheet extends StatefulWidget {
  const RecordObservationSheet({
    super.key,
    required this.repository,
    required this.deviceId,
    required this.deviceName,
    required this.latestSnapshot,
    this.events = const [],
    this.onSaved,
  });

  final EvidenceRepository repository;
  final String deviceId;
  final String deviceName;
  final DeviceSnapshot latestSnapshot;
  final List<DeviceEvent> events;
  final VoidCallback? onSaved;

  @override
  State<RecordObservationSheet> createState() => _RecordObservationSheetState();
}

class _RecordObservationSheetState extends State<RecordObservationSheet> {
  final _noteController = TextEditingController();
  final _tags = <String>{};
  var _isSaving = false;
  var _isSaved = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSave =
        _noteController.text.trim().isNotEmpty && !_isSaving && !_isSaved;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('记录观察', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                widget.deviceName,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in const ['LED', '按键', '异常'])
                    FilterChip(
                      label: Text(tag),
                      selected: _tags.contains(tag),
                      onSelected: (selected) {
                        setState(() {
                          selected ? _tags.add(tag) : _tags.remove(tag);
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                minLines: 3,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '观察备注',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _isSaved
                    ? const StatusLabel(
                        key: ValueKey('saved'),
                        icon: Icons.check_circle_outline,
                        label: '已保存',
                        kind: StatusKind.positive,
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),
              AppButton.primary(
                label: '保存',
                loading: _isSaving,
                onPressed: canSave ? _save : null,
                icon: Icons.save_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final note = _formatNote();
    final verdict = ObservationVerifier().verify(
      ObservationRun(
        scenario: ObservationScenario.physicalFeedback,
        initialSnapshot: widget.latestSnapshot,
        finalSnapshot: widget.latestSnapshot,
        manualNote: note,
      ),
    );
    final bundle = EvidenceBundle.completed(
      deviceId: widget.deviceId,
      deviceName: widget.deviceName,
      verdict: verdict.verdict,
      reason: verdict.reason,
      manualNote: note,
      records: [
        EvidenceSourceRecords.snapshot(widget.latestSnapshot),
        for (final event in widget.events) EvidenceSourceRecords.event(event),
        EvidenceSourceRecords.manualNote(note),
      ],
    );
    try {
      await widget.repository.save(bundle);
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
        AppToast.show(context, message: '保存失败，请重试。');
      }
    }
  }

  String _formatNote() {
    final prefix = _tags.isEmpty ? '' : '[${_tags.join('、')}] ';
    return '$prefix${_noteController.text.trim()}';
  }
}
