import 'package:evt_ble_app/features/evidence/application/evidence_history_controller.dart';
import 'package:evt_ble_app/features/evidence/presentation/device_activity_list.dart';
import 'package:evt_ble_app/features/local_recording/application/recording_library_controller.dart';
import 'package:evt_ble_app/features/local_recording/presentation/local_recording_list.dart';
import 'package:flutter/material.dart';

class RecordsPage extends StatefulWidget {
  const RecordsPage({
    super.key,
    required this.recordingController,
    required this.evidenceController,
    required this.onStartRecording,
  });

  final RecordingLibraryController recordingController;
  final EvidenceHistoryController evidenceController;
  final VoidCallback onStartRecording;

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  var _selection = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('记录'),
        actions: [
          IconButton(
            tooltip: '开始本机录音',
            onPressed: widget.onStartRecording,
            icon: const Icon(Icons.fiber_manual_record),
          ),
        ],
      ),
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
              child: _selection == 0
                  ? LocalRecordingList(
                      key: const ValueKey('local'),
                      controller: widget.recordingController,
                    )
                  : DeviceActivityList(
                      key: const ValueKey('activity'),
                      controller: widget.evidenceController,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
