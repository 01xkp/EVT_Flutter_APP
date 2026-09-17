import 'package:aipin/features/evidence/application/evidence_history_controller.dart';
import 'package:aipin/features/evidence/presentation/device_activity_list.dart';
import 'package:flutter/material.dart';

class RecordsPage extends StatelessWidget {
  const RecordsPage({super.key, required this.evidenceController});

  final EvidenceHistoryController evidenceController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('检查记录')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('查看手动记录的设备检查结果。录音文件请到首页的“已保存录音”；协议收发请看“实时日志”。'),
          ),
          Expanded(child: DeviceActivityList(controller: evidenceController)),
        ],
      ),
    );
  }
}
