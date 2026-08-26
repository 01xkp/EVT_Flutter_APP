import 'package:aipin/core/design_system/widgets/app_dialog.dart';
import 'package:aipin/core/design_system/widgets/status_label.dart';
import 'package:aipin/features/evidence/application/evidence_history_controller.dart';
import 'package:aipin/features/evidence/domain/evidence_bundle.dart';
import 'package:aipin/features/observation/domain/observation_verdict.dart';
import 'package:flutter/material.dart';

class EvidenceHistoryPage extends StatelessWidget {
  const EvidenceHistoryPage({super.key, required this.controller});

  final EvidenceHistoryController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        return Scaffold(
          appBar: AppBar(
            title: const Text('证据记录'),
            actions: [
              IconButton(
                tooltip: '刷新证据',
                onPressed: state.isLoading ? null : controller.load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: switch ((
            state.isLoading,
            state.items.isEmpty,
            state.errorMessage,
          )) {
            (true, true, _) => const Center(child: CircularProgressIndicator()),
            (_, _, final String errorMessage?) => _HistoryMessage(
              message: errorMessage,
            ),
            (_, true, _) => const _HistoryMessage(message: '尚无已保存的观察记录'),
            _ => ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              itemCount: state.items.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: Theme.of(context).dividerColor),
              itemBuilder: (context, index) {
                final item = state.items[index];
                return _EvidenceRow(
                  item: item,
                  onTap: () => _showDetail(context, item),
                  onDelete: () => _delete(context, item),
                );
              },
            ),
          },
        );
      },
    );
  }

  Future<void> _delete(BuildContext context, EvidenceBundle item) async {
    final approved = await AppDialog.confirmDestructive(
      context,
      title: '删除证据记录',
      message: '此操作会删除本地证据与来源记录，无法恢复。',
      confirmLabel: '删除',
    );
    if (approved) {
      await controller.delete(item.id);
    }
  }

  void _showDetail(BuildContext context, EvidenceBundle item) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.deviceName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(item.reason),
              const SizedBox(height: 8),
              Text(
                '来源记录 ${item.records.length} 条',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  final EvidenceBundle item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final verdict = switch (item.verdict) {
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
      title: Text(item.deviceName),
      subtitle: Text(item.reason, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusLabel(icon: verdict.$1, label: verdict.$2, kind: verdict.$3),
          IconButton(
            tooltip: '删除证据',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: StatusLabel(
        icon: Icons.fact_check_outlined,
        label: message,
        kind: StatusKind.neutral,
      ),
    );
  }
}
