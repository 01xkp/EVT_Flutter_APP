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
      appBar: AppBar(
        title: const Text('实时日志'),
        actions: [
          IconButton(
            tooltip: _paused ? '继续跟随' : '暂停跟随',
            onPressed: () => setState(() => _paused = !_paused),
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
          ),
          IconButton(
            tooltip: '清空视图',
            onPressed: () => widget.store.clearView(),
            icon: const Icon(Icons.clear_all),
          ),
          IconButton(
            tooltip: '导出日志',
            onPressed: _export,
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              widget.store.currentFilePath ?? 'Debug 日志文件尚未初始化',
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
    final path = await widget.store.exportPath();
    if (path != null) {
      await widget.onExport?.call(path);
    }
  }
}
