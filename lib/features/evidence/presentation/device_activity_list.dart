import 'package:aipin/features/evidence/application/evidence_history_controller.dart';
import 'package:aipin/features/observation/domain/observation_verdict.dart';
import 'package:flutter/material.dart';

class DeviceActivityList extends StatelessWidget {
  const DeviceActivityList({super.key, required this.controller});

  final EvidenceHistoryController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        if (state.isLoading && state.items.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.errorMessage case final message?) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: controller.load,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }
        if (state.items.isEmpty) {
          return const Center(child: Text('暂无检查记录'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: state.items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = state.items[index];
            final time = item.createdAt.toLocal();
            final timestamp =
                '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.deviceName),
              subtitle: Text(
                '${item.isMock ? '模拟数据 · ' : ''}${item.reason}\n$timestamp${item.manualNote == null ? '' : '\n备注：${item.manualNote}'}',
              ),
              trailing: Text(switch (item.verdict) {
                ObservationVerdict.passed => '通过',
                ObservationVerdict.failed => '未通过',
                ObservationVerdict.unverifiable => '证据不足',
              }, style: Theme.of(context).textTheme.bodySmall),
            );
          },
        );
      },
    );
  }
}
