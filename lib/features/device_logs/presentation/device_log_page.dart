import 'package:flutter/material.dart';

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

  void _toggleFollowing() {
    setState(() => _paused = !_paused);
    if (!_paused) {
      _onStoreChanged();
    }
  }

  void _clearView() {
    widget.store.clearView();
    if (mounted) {
      setState(() => entries = widget.store.entries);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('实时日志'),
        actions: [
          IconButton(
            tooltip: _paused ? '继续跟随' : '暂停跟随',
            onPressed: _toggleFollowing,
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
          ),
          IconButton(
            tooltip: '清空视图',
            onPressed: _clearView,
            icon: const Icon(Icons.clear_all),
          ),
          IconButton(
            tooltip: _exporting ? '正在导出日志' : '导出日志',
            onPressed: _exporting ? null : _export,
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _paused ? '已暂停显示，日志仍持续记录。清空视图不会删除日志文件。' : '实时显示连接、认证、录音、传输和播放事件。',
              style: Theme.of(context).textTheme.bodySmall,
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
    if (_exporting) {
      return;
    }
    setState(() => _exporting = true);
    try {
      final path = await widget.store.exportPath();
      if (!mounted) {
        return;
      }
      if (path == null) {
        throw StateError('No log file');
      }
      await widget.onExport?.call(path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('日志导出失败，请重试。')));
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
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
