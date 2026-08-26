import 'package:aipin/features/evidence/application/evidence_history_controller.dart';
import 'package:aipin/features/evidence/presentation/device_activity_list.dart';
import 'package:aipin/features/local_recording/application/recording_library_controller.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/presentation/local_recording_list.dart';
import 'package:flutter/material.dart';

class RecordsPage extends StatefulWidget {
  const RecordsPage({
    super.key,
    required this.recordingController,
    required this.evidenceController,
    this.onOpenRecording,
    this.initialSelection = 0,
  });

  final RecordingLibraryController recordingController;
  final EvidenceHistoryController evidenceController;
  final ValueChanged<LocalRecording>? onOpenRecording;
  final int initialSelection;

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  late var _selection = widget.initialSelection;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('记录')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('本机录音')),
                ButtonSegment(value: 1, label: Text('设备活动')),
              ],
              selected: {_selection},
              onSelectionChanged: (selection) =>
                  setState(() => _selection = selection.first),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: switch (_selection) {
                0 => LocalRecordingList(
                  key: const ValueKey('local'),
                  controller: widget.recordingController,
                  onOpen: widget.onOpenRecording,
                ),
                1 => DeviceActivityList(
                  key: const ValueKey('activity'),
                  controller: widget.evidenceController,
                ),
                _ => const SizedBox.shrink(),
              },
            ),
          ),
        ],
      ),
    );
  }
}
