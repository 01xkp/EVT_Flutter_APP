import 'package:aipin/features/evidence/application/evidence_history_controller.dart';
import 'package:aipin/features/evidence/presentation/device_activity_list.dart';
import 'package:flutter/material.dart';

class RecordsPage extends StatelessWidget {
  const RecordsPage({super.key, required this.evidenceController});

  final EvidenceHistoryController evidenceController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设备活动')),
      body: DeviceActivityList(controller: evidenceController),
    );
  }
}
