import 'package:evt_ble_app/features/local_recording/domain/audio_player_port.dart';
import 'package:evt_ble_app/features/local_recording/domain/local_recording.dart';
import 'package:flutter/material.dart';

class RecordingListItem extends StatelessWidget {
  const RecordingListItem({
    super.key,
    required this.recording,
    required this.isSelected,
    required this.playbackState,
    required this.onPlay,
    required this.onPause,
    required this.onRename,
    required this.onDelete,
    this.showActions = true,
  });

  final LocalRecording recording;
  final bool isSelected;
  final AudioPlaybackState playbackState;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final playing = isSelected && playbackState == AudioPlaybackState.playing;
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
        child: Row(
          children: [
            Tooltip(
              message: playing ? '暂停播放' : '播放录音',
              child: IconButton(
                tooltip: playing ? '暂停播放' : '播放录音',
                onPressed: recording.isPlayable
                    ? (playing ? onPause : onPlay)
                    : null,
                icon: Icon(
                  playing ? Icons.pause_outlined : Icons.play_arrow_outlined,
                ),
              ),
            ),
            const SizedBox(width: 8),
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
            if (showActions)
              PopupMenuButton<_RecordingAction>(
                tooltip: '更多操作',
                icon: const Icon(Icons.more_horiz),
                onSelected: (action) {
                  switch (action) {
                    case _RecordingAction.rename:
                      onRename();
                    case _RecordingAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _RecordingAction.rename,
                    child: Text('修改标题'),
                  ),
                  PopupMenuItem(
                    value: _RecordingAction.delete,
                    child: Text('删除'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _detail() {
    if (!recording.isPlayable) {
      return recording.failureReason ?? '录音不可播放';
    }
    final duration = recording.duration!;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '本机录音 · ${duration.inHours.toString().padLeft(2, '0')}:$minutes:$seconds';
  }
}

enum _RecordingAction { rename, delete }
