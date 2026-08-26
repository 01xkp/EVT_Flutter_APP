import 'package:aipin/core/design_system/widgets/app_dialog.dart';
import 'package:aipin/core/design_system/widgets/status_label.dart';
import 'package:aipin/features/local_recording/application/recording_library_controller.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/presentation/recording_list_item.dart';
import 'package:aipin/features/local_recording/presentation/rename_recording_sheet.dart';
import 'package:flutter/material.dart';

class LocalRecordingLibraryPage extends StatelessWidget {
  const LocalRecordingLibraryPage({
    super.key,
    required this.controller,
    this.onStartRecording,
    this.onOpen,
  });

  final RecordingLibraryController controller;
  final VoidCallback? onStartRecording;
  final ValueChanged<LocalRecording>? onOpen;

  @override
  Widget build(BuildContext context) {
    return _buildScaffold(context);
  }

  Widget _buildScaffold(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        return Scaffold(
          appBar: AppBar(
            title: const Text('本机录音'),
            actions: [
              IconButton(
                tooltip: '开始本机录音',
                onPressed: onStartRecording,
                icon: const Icon(Icons.fiber_manual_record),
              ),
            ],
          ),
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
                  child: _LibraryBody(
                    state: state,
                    controller: controller,
                    onRename: (recording) => _rename(context, recording),
                    onDelete: (recording) => _delete(context, recording),
                    onOpen: onOpen,
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

class _LibraryBody extends StatelessWidget {
  const _LibraryBody({
    required this.state,
    required this.controller,
    required this.onRename,
    required this.onDelete,
    this.onOpen,
  });

  final RecordingLibraryState state;
  final RecordingLibraryController controller;
  final ValueChanged<LocalRecording> onRename;
  final ValueChanged<LocalRecording> onDelete;
  final ValueChanged<LocalRecording>? onOpen;

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
            const Icon(Icons.mic_none_outlined, size: 32),
            const SizedBox(height: 12),
            Text('暂无本机录音', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: state.items.length + (state.errorMessage == null ? 0 : 1),
      separatorBuilder: (context, index) => const SizedBox(height: 10),
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
