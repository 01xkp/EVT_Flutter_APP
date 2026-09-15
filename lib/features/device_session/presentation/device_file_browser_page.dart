import 'dart:async';

import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:aipin/core/design_system/widgets/app_surface_card.dart';
import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/features/device_session/domain/device_file_import_progress.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:flutter/material.dart';

typedef DeviceFilePageLoader =
    Future<List<DeviceFile>> Function({
      required int offset,
      required int pageSize,
    });
typedef DeviceFilePageImporter =
    Future<LocalRecording> Function(
      DeviceFile file, {
      void Function(DeviceFileImportProgress progress)? onProgress,
    });

class DeviceFileBrowserPage extends StatefulWidget {
  const DeviceFileBrowserPage({
    super.key,
    required this.onListFiles,
    required this.onImport,
    this.onOpenSavedRecordings,
  });

  final DeviceFilePageLoader onListFiles;
  final DeviceFilePageImporter onImport;
  final Future<void> Function()? onOpenSavedRecordings;

  @override
  State<DeviceFileBrowserPage> createState() => _DeviceFileBrowserPageState();
}

class _DeviceFileBrowserPageState extends State<DeviceFileBrowserPage> {
  final _files = <DeviceFile>[];
  final _progress = <String, DeviceFileImportProgress>{};
  final _importing = <String>{};
  String? _error;
  var _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设备录音文件'),
        actions: [
          if (widget.onOpenSavedRecordings case final openSaved?)
            IconButton(
              tooltip: '查看已保存录音',
              onPressed: () => unawaited(openSaved()),
              icon: const Icon(Icons.folder_open_outlined),
            ),
          IconButton(
            tooltip: '刷新文件列表',
            onPressed: _loading || _importing.isNotEmpty
                ? null
                : () => unawaited(_load()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading && _files.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: _files.isEmpty
                    ? ListView(
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * .7,
                            child: Center(child: Text(_error ?? '设备中暂无可导入的录音')),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: _files.length + (_error == null ? 0 : 1),
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          if (_error != null && index == 0) {
                            return Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            );
                          }
                          final file =
                              _files[_error == null ? index : index - 1];
                          return _DeviceFileTile(
                            file: file,
                            progress: _progress[file.name],
                            isImporting: _importing.contains(file.name),
                            onImport: _loading || _importing.isNotEmpty
                                ? null
                                : () => unawaited(_import(file)),
                          );
                        },
                      ),
              ),
      ),
    );
  }

  Future<void> _load() async {
    if (!mounted || _loading || _importing.isNotEmpty) return;
    setState(() => _loading = true);
    try {
      final loaded = <DeviceFile>[];
      final seenFileSlots = <String>{};
      var offset = 0;
      while (true) {
        final page = await widget.onListFiles(offset: offset, pageSize: 20);
        if (!mounted) return;
        if (page.isEmpty) break;
        for (final file in page) {
          if (!seenFileSlots.add(file.nameSlot.join(','))) {
            throw StateError('设备文件列表返回了重复文件键。');
          }
        }
        if (page.length > 0xFFFF - offset) {
          throw StateError('设备文件列表超出了协议允许的偏移范围。');
        }
        loaded.addAll(page);
        offset += page.length;
      }
      if (mounted) {
        setState(() {
          _files
            ..clear()
            ..addAll(loaded);
          _error = null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '设备录音列表暂时不可读取，请重试';
          _loading = false;
        });
      }
    }
  }

  Future<void> _import(DeviceFile file) async {
    // V1.6 permits one active file transfer per connection. Reserve the
    // browser before awaiting local checkpoint or BLE work.
    if (!mounted || _loading || _importing.isNotEmpty) return;
    setState(() {
      _importing.add(file.name);
      _progress.remove(file.name);
    });
    try {
      await widget.onImport(
        file,
        onProgress: (progress) {
          if (mounted) setState(() => _progress[file.name] = progress);
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('设备录音已保存到 App')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('设备文件导入失败，请重试')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _importing.remove(file.name);
          _progress.remove(file.name);
        });
      }
    }
  }
}

class _DeviceFileTile extends StatelessWidget {
  const _DeviceFileTile({
    required this.file,
    required this.progress,
    required this.isImporting,
    required this.onImport,
  });

  final DeviceFile file;
  final DeviceFileImportProgress? progress;
  final bool isImporting;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.audio_file_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(_formatBytes(file.length)),
            ],
          ),
          const SizedBox(height: 12),
          AppButton.secondary(
            label: isImporting ? '正在保存' : '保存到 App',
            icon: isImporting
                ? Icons.downloading_outlined
                : Icons.download_outlined,
            onPressed: isImporting ? null : onImport,
          ),
          if (progress case final value?) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: value.fraction),
            const SizedBox(height: 4),
            Text(
              '${value.received}/${value.total} B',
              textAlign: TextAlign.right,
            ),
          ],
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
