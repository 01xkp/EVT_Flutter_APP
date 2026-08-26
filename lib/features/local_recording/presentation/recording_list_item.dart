import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:flutter/material.dart';

class RecordingListItem extends StatelessWidget {
  const RecordingListItem({
    super.key,
    required this.recording,
    this.onOpen,
    this.onRename,
    this.onDelete,
    this.showActions = true,
    this.showRenameAction = true,
    this.showDeleteAction = true,
    this.showDeleteButton = false,
  });

  final LocalRecording recording;
  final VoidCallback? onOpen;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final bool showActions;
  final bool showRenameAction;
  final bool showDeleteAction;
  final bool showDeleteButton;

  @override
  Widget build(BuildContext context) {
    final canRename = showRenameAction && onRename != null;
    final canDelete = onDelete != null;
    final canDeleteFromMenu = showDeleteAction && canDelete;
    return Card(
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 6, 12),
          child: Row(
            children: [
              const Icon(Icons.graphic_eq_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recording.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _detail(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (showActions && (canRename || canDeleteFromMenu))
                PopupMenuButton<_RecordingAction>(
                  tooltip: '更多操作',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (action) {
                    switch (action) {
                      case _RecordingAction.rename:
                        onRename?.call();
                      case _RecordingAction.delete:
                        onDelete?.call();
                    }
                  },
                  itemBuilder: (context) => [
                    if (canRename)
                      const PopupMenuItem(
                        value: _RecordingAction.rename,
                        child: Text('重命名'),
                      ),
                    if (canDeleteFromMenu)
                      const PopupMenuItem(
                        value: _RecordingAction.delete,
                        child: Text('删除'),
                      ),
                  ],
                ),
              if (showDeleteButton && canDelete)
                IconButton(
                  tooltip: '删除录音',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _detail() {
    final createdAt = recording.createdAt;
    final created =
        '${createdAt.year.toString().padLeft(4, '0')}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
    if (!recording.isPlayable) {
      return '$created · ${_statusLabel()} · ${recording.failureReason ?? '录音不可播放'}';
    }
    final duration = recording.duration!;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$created · ${duration.inHours.toString().padLeft(2, '0')}:$minutes:$seconds · ${_formatSize(recording.sizeBytes!)} · ${_statusLabel()}';
  }

  String _statusLabel() => switch (recording.status) {
    LocalRecordingStatus.inProgress => '正在保存',
    LocalRecordingStatus.saved => '已保存',
    LocalRecordingStatus.interrupted => '已中断',
    LocalRecordingStatus.failed => '无法播放',
  };

  String _formatSize(int sizeBytes) {
    if (sizeBytes < 1000) {
      return '$sizeBytes B';
    }
    final kilobytes = sizeBytes / 1000;
    return kilobytes == kilobytes.roundToDouble()
        ? '${kilobytes.toStringAsFixed(0)} KB'
        : '${kilobytes.toStringAsFixed(1)} KB';
  }
}

enum _RecordingAction { rename, delete }
