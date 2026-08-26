import 'package:aipin/features/evidence/application/evidence_history_controller.dart';
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
        if (state.items.isEmpty) {
          return const Center(child: Text('暂无设备活动'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: state.items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = state.items[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text('已完成设备检查'),
              subtitle: Text(item.deviceName),
              trailing: Text(
                TimeOfDay.fromDateTime(item.createdAt).format(context),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          },
        );
      },
    );
  }
}
