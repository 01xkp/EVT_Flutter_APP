import 'dart:async';

import 'package:aipin/core/design_system/widgets/app_dialog.dart';
import 'package:aipin/features/local_recording/application/recording_library_controller.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/presentation/recording_list_item.dart';
import 'package:aipin/features/local_recording/presentation/rename_recording_sheet.dart';
import 'package:flutter/material.dart';

class LocalRecordingList extends StatelessWidget {
  const LocalRecordingList({super.key, required this.controller, this.onOpen});

  final RecordingLibraryController controller;
  final ValueChanged<LocalRecording>? onOpen;

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
              onOpen: onOpen == null ? null : () => onOpen!(recording),
              showActions: true,
              showDeleteAction: false,
              showDeleteButton: true,
              onRename: () => unawaited(_rename(context, recording)),
              onDelete: () => unawaited(_delete(context, recording)),
            );
          },
        );
      },
    );
  }

  Future<void> _delete(BuildContext context, LocalRecording recording) async {
    final approved = await AppDialog.confirmDestructive(
      context,
      title: '删除这条录音？',
      message: '删除后将无法恢复本机音频文件。',
      confirmLabel: '删除',
    );
    if (approved) {
      await controller.delete(recording);
    }
  }

  Future<void> _rename(BuildContext context, LocalRecording recording) async {
    final value = await RenameRecordingSheet.show(
      context,
      title: recording.title,
    );
    if (value != null) {
      await controller.rename(recording, value);
    }
  }
}
