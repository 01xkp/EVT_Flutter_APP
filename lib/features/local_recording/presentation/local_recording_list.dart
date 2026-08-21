import 'dart:async';

import 'package:evt_ble_app/features/local_recording/application/recording_library_controller.dart';
import 'package:evt_ble_app/features/local_recording/presentation/recording_list_item.dart';
import 'package:flutter/material.dart';

class LocalRecordingList extends StatelessWidget {
  const LocalRecordingList({super.key, required this.controller});

  final RecordingLibraryController controller;

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
          return const Center(child: Text('暂无本机录音'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: state.items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final recording = state.items[index];
            return RecordingListItem(
              recording: recording,
              isSelected: state.selectedPlaybackId == recording.id,
              playbackState: state.playbackState,
              onPlay: () => unawaited(controller.play(recording.id)),
              onPause: () => unawaited(controller.pause()),
              onRename: () {},
              onDelete: () {},
              showActions: false,
            );
          },
        );
      },
    );
  }
}
