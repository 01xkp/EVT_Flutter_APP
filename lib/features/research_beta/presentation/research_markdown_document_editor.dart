import 'package:aipin/features/research_beta/presentation/research_document_actions.dart';
import 'package:aipin/features/research_beta/presentation/research_editor_mode_toggle.dart';
import 'package:aipin/features/research_beta/presentation/research_markdown_editing.dart';
import 'package:aipin/features/research_beta/presentation/research_markdown_preview.dart';
import 'package:flutter/material.dart';

class ResearchMarkdownDocumentEditor extends StatefulWidget {
  const ResearchMarkdownDocumentEditor({
    super.key,
    required this.source,
    required this.onSave,
    this.title = 'AI 总结',
    this.onRegenerate,
    this.onRename,
    this.onCopy,
    this.onExport,
  });

  final String source;
  final Future<void> Function(String value) onSave;
  final String title;
  final Future<void> Function()? onRegenerate;
  final Future<void> Function()? onRename;
  final Future<void> Function(String value)? onCopy;
  final Future<void> Function(String value)? onExport;

  @override
  State<ResearchMarkdownDocumentEditor> createState() =>
      _ResearchMarkdownDocumentEditorState();
}

class _ResearchMarkdownDocumentEditorState
    extends State<ResearchMarkdownDocumentEditor> {
  late final TextEditingController _controller;
  var _isEditing = false;
  var _isPreviewing = false;
  var _isSaving = false;
  var _isRegenerating = false;
  var _isRunningDocumentAction = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.source);
  }

  @override
  void didUpdateWidget(covariant ResearchMarkdownDocumentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && oldWidget.source != widget.source) {
      _controller.text = widget.source;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (widget.onRename != null)
                    IconButton(
                      tooltip: '重命名总结',
                      onPressed: _isEditing || _isSaving ? null : _rename,
                      icon: const Icon(Icons.drive_file_rename_outline),
                    ),
                ],
              ),
            ),
            ResearchEditorModeToggle(
              label: '总结',
              isEditing: _isEditing,
              isPreviewing: _isPreviewing,
              isSaving: _isSaving,
              onStartEditing: _startEditing,
              onShowEditor: _showEditor,
              onShowPreview: _showPreview,
            ),
            if (widget.onRegenerate != null)
              IconButton(
                tooltip: '重新生成总结',
                onPressed: _isEditing || _isSaving || _isRegenerating
                    ? null
                    : _regenerate,
                icon: _isRegenerating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_outlined),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isEditing && !_isPreviewing) ...[
          _FormattingToolbar(
            onApplyLinePrefix: _applyLinePrefix,
            onApplyInline: _applyInline,
            onInsertDivider: _insertDivider,
            onInsertLink: _showLinkDialog,
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('markdown-summary-input'),
            controller: _controller,
            minLines: 8,
            maxLines: 14,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: '使用 Markdown 编辑总结',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ] else
          ResearchMarkdownPreview(source: _controller.text),
        if (!_isEditing || _isPreviewing) ...[
          const SizedBox(height: 4),
          ResearchDocumentActions(
            label: '总结',
            isProcessing: _isRunningDocumentAction,
            onCopy: widget.onCopy == null
                ? null
                : () => _runDocumentAction(widget.onCopy!),
            onExport: widget.onExport == null
                ? null
                : () => _runDocumentAction(widget.onExport!),
          ),
        ],
        if (_isEditing && !_isPreviewing) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _isSaving ? null : _cancel,
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _cancel() {
    setState(() {
      _controller.text = widget.source;
      _isEditing = false;
      _isPreviewing = false;
    });
  }

  Future<void> _regenerate() async {
    final regenerate = widget.onRegenerate;
    if (regenerate == null || _isRegenerating) {
      return;
    }
    setState(() => _isRegenerating = true);
    try {
      await regenerate();
    } finally {
      if (mounted) {
        setState(() => _isRegenerating = false);
      }
    }
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _isPreviewing = false;
    });
  }

  void _showEditor() => setState(() => _isPreviewing = false);

  void _showPreview() => setState(() => _isPreviewing = true);

  Future<void> _rename() async {
    final rename = widget.onRename;
    if (rename != null) {
      await rename();
    }
  }

  void _applyLinePrefix(String prefix) => _updateEditingValue(
    ResearchMarkdownEditing.applyLinePrefix(_controller.value, prefix),
  );

  void _applyInline({
    required String marker,
    required String placeholder,
    String? closingMarker,
  }) => _updateEditingValue(
    ResearchMarkdownEditing.applyInline(
      _controller.value,
      marker: marker,
      closingMarker: closingMarker,
      placeholder: placeholder,
    ),
  );

  void _insertDivider() => _updateEditingValue(
    ResearchMarkdownEditing.insertDivider(_controller.value),
  );

  void _updateEditingValue(TextEditingValue value) {
    _controller.value = value;
    setState(() {});
  }

  Future<void> _showLinkDialog() async {
    final urlController = TextEditingController();
    final labelController = TextEditingController();
    final result = await showDialog<_MarkdownLinkData>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('插入链接'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('markdown-link-url'),
              controller: urlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: '链接地址'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('markdown-link-label'),
              controller: labelController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: '显示文字（可选）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final url = urlController.text.trim();
              if (!_isHttpUrl(url)) {
                return;
              }
              Navigator.of(context).pop(
                _MarkdownLinkData(url: url, label: labelController.text.trim()),
              );
            },
            child: const Text('插入'),
          ),
        ],
      ),
    );
    urlController.dispose();
    labelController.dispose();
    if (result == null || !mounted) {
      return;
    }
    _updateEditingValue(
      ResearchMarkdownEditing.insertLink(
        _controller.value,
        url: result.url,
        fallbackLabel: result.label.isEmpty ? '链接文字' : result.label,
      ),
    );
  }

  bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.hasAuthority &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Future<void> _runDocumentAction(
    Future<void> Function(String value) action,
  ) async {
    if (_isRunningDocumentAction) {
      return;
    }
    setState(() => _isRunningDocumentAction = true);
    try {
      await action(_controller.text);
    } finally {
      if (mounted) {
        setState(() => _isRunningDocumentAction = false);
      }
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await widget.onSave(_controller.text.trim());
      if (mounted) {
        setState(() {
          _isEditing = false;
          _isPreviewing = false;
        });
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _FormattingToolbar extends StatelessWidget {
  const _FormattingToolbar({
    required this.onApplyLinePrefix,
    required this.onApplyInline,
    required this.onInsertDivider,
    required this.onInsertLink,
  });

  final ValueChanged<String> onApplyLinePrefix;
  final void Function({
    required String marker,
    required String placeholder,
    String? closingMarker,
  })
  onApplyInline;
  final VoidCallback onInsertDivider;
  final Future<void> Function() onInsertLink;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          key: const ValueKey('markdown-format-row-1'),
          children: [
            _action(
              tooltip: '一级标题',
              icon: Icons.title,
              onPressed: () =>
                  onApplyLinePrefix(ResearchMarkdownEditing.headingOnePrefix),
            ),
            _action(
              tooltip: '二级标题',
              icon: Icons.format_size,
              onPressed: () =>
                  onApplyLinePrefix(ResearchMarkdownEditing.headingTwoPrefix),
            ),
            _action(
              tooltip: '加粗',
              icon: Icons.format_bold,
              onPressed: () => onApplyInline(
                marker: ResearchMarkdownEditing.boldMarker,
                placeholder: '加粗文字',
              ),
            ),
            _action(
              tooltip: '斜体',
              icon: Icons.format_italic,
              onPressed: () => onApplyInline(
                marker: ResearchMarkdownEditing.italicMarker,
                placeholder: '斜体文字',
              ),
            ),
            _action(
              tooltip: '下划线',
              icon: Icons.format_underlined,
              onPressed: () => onApplyInline(
                marker: ResearchMarkdownEditing.underlineMarker,
                closingMarker: ResearchMarkdownEditing.underlineClosingMarker,
                placeholder: '下划线文字',
              ),
            ),
            _action(
              tooltip: '无序列表',
              icon: Icons.format_list_bulleted,
              onPressed: () => onApplyLinePrefix(
                ResearchMarkdownEditing.unorderedListPrefix,
              ),
            ),
          ],
        ),
        Row(
          key: const ValueKey('markdown-format-row-2'),
          children: [
            _action(
              tooltip: '有序列表',
              icon: Icons.format_list_numbered,
              onPressed: () =>
                  onApplyLinePrefix(ResearchMarkdownEditing.orderedListPrefix),
            ),
            _action(
              tooltip: '待办项',
              icon: Icons.checklist,
              onPressed: () =>
                  onApplyLinePrefix(ResearchMarkdownEditing.checklistPrefix),
            ),
            _action(
              tooltip: '引用',
              icon: Icons.format_quote,
              onPressed: () =>
                  onApplyLinePrefix(ResearchMarkdownEditing.quotePrefix),
            ),
            _action(
              tooltip: '分割线',
              icon: Icons.horizontal_rule,
              onPressed: onInsertDivider,
            ),
            _action(
              tooltip: '插入链接',
              icon: Icons.link,
              onPressed: () => onInsertLink(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _action({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: SizedBox(
        height: 44,
        child: IconButton(
          tooltip: tooltip,
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      ),
    );
  }
}

class _MarkdownLinkData {
  const _MarkdownLinkData({required this.url, required this.label});

  final String url;
  final String label;
}
