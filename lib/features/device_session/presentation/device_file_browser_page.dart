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
    this.onOpenRecording,
    this.isSavedRecordingAvailable,
    this.onMetadata,
    this.onArchive,
    this.onListPendingArchives,
    this.onRetryArchive,
  });

  final DeviceFilePageLoader onListFiles;
  final DeviceFilePageImporter onImport;
  final Future<void> Function()? onOpenSavedRecordings;
  final Future<void> Function(LocalRecording recording)? onOpenRecording;
  final Future<bool> Function(LocalRecording recording)?
  isSavedRecordingAvailable;
  final Future<DvtDeviceFileMetadata> Function(DeviceFile)? onMetadata;
  final Future<String> Function(DeviceFile)? onArchive;
  final Future<List<DeviceFile>> Function()? onListPendingArchives;
  final Future<String> Function(DeviceFile)? onRetryArchive;

  @override
  State<DeviceFileBrowserPage> createState() => _DeviceFileBrowserPageState();
}

class _DeviceFileBrowserPageState extends State<DeviceFileBrowserPage> {
  final _files = <DeviceFile>[];
  final _pendingArchives = <DeviceFile>[];
  final _progress = <String, DeviceFileImportProgress>{};
  final _importing = <String>{};
  final _saved = <String, LocalRecording>{};
  String? _error;
  var _loading = true;
  bool _actionBusy = false;
  bool _loadRunning = false;

  bool get _busy => _loading || _actionBusy || _importing.isNotEmpty;
  String _fileKey(DeviceFile file) => file.nameSlot.join(',');

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设备文件'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  _loading
                      ? '正在读取设备文件…'
                      : '设备上共 ${_files.length} 个文件。保存到手机后可直接播放。',
                ),
              ),
              if (_actionBusy) const LinearProgressIndicator(minHeight: 3),
            ],
          ),
        ),
        actions: [
          if (widget.onOpenSavedRecordings case final openSaved?)
            Tooltip(
              message: '查看已保存录音',
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => unawaited(_openSavedRecordings(openSaved)),
                child: const Text('已保存录音'),
              ),
            ),
          Tooltip(
            message: '刷新文件列表',
            child: TextButton(
              onPressed: _busy ? null : () => unawaited(_load()),
              child: const Text('刷新'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading && _files.isEmpty && _pendingArchives.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_pendingArchives.isNotEmpty) ...[
                      const Text('本地待归档确认'),
                      const Text('保留原文件键、大小和 CRC。即使设备文件已删除，也可重新确认归档结果。'),
                      for (final file in _pendingArchives)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: TextButton(
                            onPressed: _busy || widget.onRetryArchive == null
                                ? null
                                : () =>
                                      unawaited(_archive(file, recovery: true)),
                            child: const Text('继续归档'),
                          ),
                        ),
                      const Divider(),
                    ],
                    if (_files.isEmpty && _error == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Text('设备中暂无可导入的录音'),
                      ),
                    for (final file in _files)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _DeviceFileTile(
                          file: file,
                          progress: _progress[_fileKey(file)],
                          isImporting: _importing.contains(_fileKey(file)),
                          isSaved: _saved.containsKey(_fileKey(file)),
                          actionsEnabled: !_busy,
                          onPlay:
                              widget.onOpenRecording != null &&
                                  _saved.containsKey(_fileKey(file))
                              ? () => unawaited(_openRecording(_fileKey(file)))
                              : null,
                          onImport: _busy
                              ? null
                              : () => unawaited(_import(file)),
                          onMetadata: widget.onMetadata == null
                              ? null
                              : () => unawaited(_showMetadata(file)),
                          onArchive: widget.onArchive == null
                              ? null
                              : () => unawaited(_archive(file)),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _openSavedRecordings(Future<void> Function() openSaved) async {
    await openSaved();
    await _reconcileSavedRecordings();
  }

  Future<void> _openRecording(String key) async {
    if (!await _reconcileSavedRecordings() || !mounted) return;
    final recording = _saved[key];
    if (recording == null) return;
    await widget.onOpenRecording?.call(recording);
    await _reconcileSavedRecordings();
  }

  Future<bool> _reconcileSavedRecordings() async {
    final isAvailable = widget.isSavedRecordingAvailable;
    if (!mounted || isAvailable == null) return mounted;
    try {
      final missing = <String>[];
      for (final entry in _saved.entries.toList()) {
        if (!await isAvailable(entry.value)) missing.add(entry.key);
        if (!mounted) return false;
      }
      if (missing.isNotEmpty) {
        setState(() {
          for (final key in missing) {
            _saved.remove(key);
          }
        });
      }
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('手机录音暂时不可读取，请重试')));
      }
      return false;
    }
  }

  Future<void> _load() async {
    if (!mounted || _loadRunning || _actionBusy || _importing.isNotEmpty) {
      return;
    }
    _loadRunning = true;
    if (mounted) setState(() => _loading = true);
    try {
      final pending =
          await widget.onListPendingArchives?.call() ?? const <DeviceFile>[];
      if (!mounted) return;
      if (mounted) {
        setState(
          () => _pendingArchives
            ..clear()
            ..addAll(pending),
        );
      }
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
      await _reconcileSavedRecordings();
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
    } finally {
      _loadRunning = false;
    }
  }

  Future<void> _import(DeviceFile file) async {
    if (!mounted || _busy) return;
    final key = _fileKey(file);
    setState(() {
      _importing.add(key);
      _progress.remove(key);
    });
    try {
      final saved = await widget.onImport(
        file,
        onProgress: (progress) {
          if (mounted) setState(() => _progress[key] = progress);
        },
      );
      if (mounted) {
        setState(() => _saved[key] = saved);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('设备录音已保存到 App')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('设备文件导入失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _importing.remove(key);
          _progress.remove(key);
        });
        await _load();
      }
    }
  }

  Future<void> _showMetadata(DeviceFile file) async {
    if (!mounted || _busy) return;
    setState(() => _actionBusy = true);
    try {
      final meta = await widget.onMetadata!(file);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('文件元数据 · 0x26'),
          content: SingleChildScrollView(
            child: SelectableText(
              '文件：${meta.name}\n大小：${meta.fileSize} B\n'
              'CRC32：${meta.crc32.toRadixString(16).padLeft(8, '0').toUpperCase()}\n'
              '状态：${meta.state.name} (${meta.state.wireValue})\n'
              '起始时间 UTC：${meta.startUtc.toIso8601String()}\n'
              '录音会话：${meta.recordingSessionId}\n分段序号：${meta.segmentIndex}\n'
              '时钟质量：${meta.clockQuality}\nUTC修正：${meta.utcCorrectionMilliseconds} ms\n'
              '文件键字节：${meta.nameSlot.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _archive(DeviceFile file, {bool recovery = false}) async {
    if (!mounted || _busy) return;
    setState(() => _actionBusy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('归档设备录音'),
          content: const Text(
            '校验本地录音并确认云端可靠保存后，通知设备释放源文件。回包丢失时保留本地恢复记录；设备源文件可能已经释放，可重连后继续确认。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('归档'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final message = await (recovery
          ? widget.onRetryArchive!
          : widget.onArchive!)(file);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('归档未完成：$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _actionBusy = false);
        await _load();
      }
    }
  }
}

class _DeviceFileTile extends StatelessWidget {
  const _DeviceFileTile({
    required this.file,
    required this.progress,
    required this.isImporting,
    required this.isSaved,
    required this.actionsEnabled,
    required this.onImport,
    this.onPlay,
    this.onMetadata,
    this.onArchive,
  });

  final DeviceFile file;
  final DeviceFileImportProgress? progress;
  final bool isImporting;
  final bool isSaved;
  final bool actionsEnabled;
  final VoidCallback? onImport;
  final VoidCallback? onPlay;
  final VoidCallback? onMetadata;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
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
          if (isSaved) ...[
            const Text('已保存到手机'),
            if (onPlay != null)
              AppButton.primary(
                label: '播放',
                onPressed: actionsEnabled ? onPlay : null,
              ),
          ] else
            AppButton.secondary(
              label: isImporting ? '正在保存' : '保存到 App',
              onPressed: isImporting ? null : onImport,
            ),
          if (onMetadata != null || onArchive != null)
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (onMetadata != null)
                  TextButton.icon(
                    onPressed: actionsEnabled ? onMetadata : null,
                    icon: const Icon(Icons.info_outline),
                    label: const Text('元数据'),
                  ),
                if (onArchive != null)
                  TextButton.icon(
                    onPressed: actionsEnabled ? onArchive : null,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('归档并释放'),
                  ),
              ],
            ),
          if (progress case final value?) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: value.fraction),
            const SizedBox(height: 4),
            Text(
              '${(value.fraction * 100).toStringAsFixed(0)}% · ${value.received}/${value.total} B',
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
