import 'package:aipin/core/design_system/widgets/app_dialog.dart';
import 'package:aipin/core/design_system/widgets/status_label.dart';
import 'package:aipin/features/local_recording/application/recording_library_controller.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/presentation/recording_list_item.dart';
import 'package:aipin/features/local_recording/presentation/rename_recording_sheet.dart';
import 'package:flutter/material.dart';

/// Lists audio previously saved by the EVT device-file transfer flow.
/// It intentionally provides no local capture action.
class DeviceRecordingLibraryPage extends StatelessWidget {
  const DeviceRecordingLibraryPage({
    super.key,
    required this.controller,
    this.onOpen,
  });

  final RecordingLibraryController controller;
  final ValueChanged<LocalRecording>? onOpen;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        return Scaffold(
          appBar: AppBar(title: const Text('已保存录音')),
          body: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth > 600
                        ? 760
                        : double.infinity,
                  ),
                  child: _DeviceRecordingLibraryBody(
                    state: state,
                    onOpen: onOpen,
                    onRename: (recording) => _rename(context, recording),
                    onDelete: (recording) => _delete(context, recording),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _delete(BuildContext context, LocalRecording recording) async {
    final approved = await AppDialog.confirmDestructive(
      context,
      title: '删除这条已保存录音？',
      message: '删除后将无法恢复已保存的音频文件。',
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

class _DeviceRecordingLibraryBody extends StatelessWidget {
  const _DeviceRecordingLibraryBody({
    required this.state,
    required this.onRename,
    required this.onDelete,
    this.onOpen,
  });

  final RecordingLibraryState state;
  final ValueChanged<LocalRecording>? onOpen;
  final ValueChanged<LocalRecording> onRename;
  final ValueChanged<LocalRecording> onDelete;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.audio_file_outlined, size: 32),
            const SizedBox(height: 12),
            Text('暂无已保存录音', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: state.items.length + (state.errorMessage == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (state.errorMessage != null && index == 0) {
          return StatusLabel(
            icon: Icons.error_outline,
            label: state.errorMessage!,
            kind: StatusKind.danger,
          );
        }
        final itemIndex = state.errorMessage == null ? index : index - 1;
        final recording = state.items[itemIndex];
        return RecordingListItem(
          recording: recording,
          onOpen: onOpen == null ? null : () => onOpen!(recording),
          onRename: () => onRename(recording),
          onDelete: () => onDelete(recording),
        );
      },
    );
  }
}
