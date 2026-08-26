import 'package:aipin/features/research_beta/presentation/research_document_actions.dart';
import 'package:aipin/features/research_beta/presentation/research_editor_mode_toggle.dart';
import 'package:flutter/material.dart';

class ResearchMarkdownDocumentEditor extends StatefulWidget {
  const ResearchMarkdownDocumentEditor({
    super.key,
    required this.source,
    required this.onSave,
    this.onRegenerate,
    this.onCopy,
    this.onExport,
  });

  final String source;
  final Future<void> Function(String value) onSave;
  final Future<void> Function()? onRegenerate;
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
              child: Text(
                'AI 总结',
                style: Theme.of(context).textTheme.titleSmall,
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
            onHeading: () => _insertAtLineStart('# '),
            onBullet: () => _insertAtLineStart('- '),
            onBold: _insertBold,
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
          _MarkdownPreview(source: _controller.text),
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

  void _insertAtLineStart(String prefix) {
    final value = _controller.value;
    final selectionStart = value.selection.start < 0
        ? 0
        : value.selection.start;
    final lineStart = selectionStart == 0
        ? 0
        : value.text.lastIndexOf('\n', selectionStart - 1) + 1;
    final updated =
        '${value.text.substring(0, lineStart)}$prefix'
        '${value.text.substring(lineStart)}';
    _controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(
        offset: selectionStart + prefix.length,
      ),
    );
    setState(() {});
  }

  void _insertBold() {
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.start < 0 ? 0 : selection.start;
    final end = selection.end < 0 ? start : selection.end;
    final selected = value.text.substring(start, end);
    const markers = '**';
    final updated =
        '${value.text.substring(0, start)}$markers'
        '${selected.isEmpty ? '加粗文字' : selected}$markers'
        '${value.text.substring(end)}';
    _controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(
        offset:
            start + markers.length + (selected.isEmpty ? 4 : selected.length),
      ),
    );
    setState(() {});
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
    required this.onHeading,
    required this.onBullet,
    required this.onBold,
  });

  final VoidCallback onHeading;
  final VoidCallback onBullet;
  final VoidCallback onBold;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: '添加一级标题',
          onPressed: onHeading,
          icon: const Icon(Icons.title),
        ),
        IconButton(
          tooltip: '添加项目符号',
          onPressed: onBullet,
          icon: const Icon(Icons.format_list_bulleted),
        ),
        IconButton(
          tooltip: '添加加粗文字',
          onPressed: onBold,
          icon: const Icon(Icons.format_bold),
        ),
      ],
    );
  }
}

class _MarkdownPreview extends StatelessWidget {
  const _MarkdownPreview({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = source.split('\n');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            _MarkdownPreviewLine(line: line, theme: theme),
        ],
      ),
    );
  }
}

class _MarkdownPreviewLine extends StatelessWidget {
  const _MarkdownPreviewLine({required this.line, required this.theme});

  final String line;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final heading = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(line);
    if (heading != null) {
      final level = heading.group(1)!.length;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _MarkdownInlineText(
          source: heading.group(2)!,
          style: switch (level) {
            1 => theme.textTheme.titleLarge,
            2 => theme.textTheme.titleMedium,
            _ => theme.textTheme.titleSmall,
          },
        ),
      );
    }

    final bullet = RegExp(r'^(\s*)-\s+(.+)$').firstMatch(line);
    if (bullet != null) {
      final indent = bullet.group(1)!.length ~/ 2;
      return Padding(
        padding: EdgeInsets.only(left: indent * 16.0, bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• '),
            Expanded(child: _MarkdownInlineText(source: bullet.group(2)!)),
          ],
        ),
      );
    }

    if (line.isEmpty) {
      return const SizedBox(height: 4);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _MarkdownInlineText(source: line),
    );
  }
}

class _MarkdownInlineText extends StatelessWidget {
  const _MarkdownInlineText({required this.source, this.style});

  final String source;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (!source.contains('**')) {
      return Text(source, style: style);
    }
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    var offset = 0;
    for (final match in pattern.allMatches(source)) {
      if (match.start > offset) {
        spans.add(TextSpan(text: source.substring(offset, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      );
      offset = match.end;
    }
    if (offset < source.length) {
      spans.add(TextSpan(text: source.substring(offset)));
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }
}
