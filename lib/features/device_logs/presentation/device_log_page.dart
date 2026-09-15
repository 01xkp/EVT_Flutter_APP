import 'package:flutter/material.dart';
import 'package:aipin/core/design_system/widgets/app_text_action.dart';

import '../data/file_app_log_store.dart';
import '../domain/app_log_entry.dart';

class DeviceLogPage extends StatefulWidget {
  const DeviceLogPage({super.key, required this.store, this.onExport});

  final FileAppLogStore store;
  final Future<void> Function(String path)? onExport;

  @override
  State<DeviceLogPage> createState() => _DeviceLogPageState();
}

class _DeviceLogPageState extends State<DeviceLogPage> {
  final _scrollController = ScrollController();
  var _paused = false;
  var _exporting = false;
  List<AppLogEntry> entries = const [];

  @override
  void initState() {
    super.initState();
    entries = widget.store.entries;
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (!mounted || _paused) {
      return;
    }
    setState(() => entries = widget.store.entries);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('实时日志')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            children: [
              AppTextAction(
                label: _paused ? '继续跟随' : '暂停跟随',
                onPressed: () {
                  setState(() => _paused = !_paused);
                  if (!_paused) _onStoreChanged();
                },
              ),
              AppTextAction(
                label: '清空视图',
                onPressed: () {
                  widget.store.clearView();
                  setState(() => entries = widget.store.entries);
                },
              ),
              AppTextAction(
                label: _exporting ? '正在导出' : '导出日志',
                onPressed: _exporting ? null : _export,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _paused ? '已暂停显示，日志仍持续记录。清空视图不会删除日志文件。' : '实时显示连接、认证、录音、传输和播放事件。',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              _logFileLocation(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const Center(child: Text('暂无日志'))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: entries.length,
                    itemBuilder: (context, index) => SelectableText(
                      entries[index].formatLine(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final path = await widget.store.exportPath();
      if (!mounted) return;
      if (path == null) throw StateError('No log file');
      await widget.onExport?.call(path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('日志导出失败，请重试。')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _logFileLocation() {
    final mirror = widget.store.publicMirrorStatus;
    final publicPath = mirror?.available == true ? mirror?.relativePath : null;
    if (publicPath != null) {
      return '已保存到：$publicPath';
    }
    final canonicalPath = widget.store.currentFilePath;
    if (canonicalPath != null) {
      return '应用内部日志：$canonicalPath';
    }
    return 'Debug 日志文件尚未初始化';
  }
}
