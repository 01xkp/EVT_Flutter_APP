import 'package:aipin/features/research_beta/presentation/research_document_actions.dart';
import 'package:aipin/features/research_beta/presentation/research_editor_mode_toggle.dart';
import 'package:flutter/material.dart';

class ResearchTranscriptEditor extends StatefulWidget {
  const ResearchTranscriptEditor({
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
  State<ResearchTranscriptEditor> createState() =>
      _ResearchTranscriptEditorState();
}

class _ResearchTranscriptEditorState extends State<ResearchTranscriptEditor> {
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
  void didUpdateWidget(covariant ResearchTranscriptEditor oldWidget) {
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
              child: Text('转写', style: Theme.of(context).textTheme.titleSmall),
            ),
            ResearchEditorModeToggle(
              label: '转写',
              isEditing: _isEditing,
              isPreviewing: _isPreviewing,
              isSaving: _isSaving,
              onStartEditing: _startEditing,
              onShowEditor: _showEditor,
              onShowPreview: _showPreview,
            ),
            if (widget.onRegenerate != null)
              IconButton(
                tooltip: '重新生成转写',
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
        if (_isEditing && !_isPreviewing)
          TextField(
            key: const ValueKey('transcript-input'),
            controller: _controller,
            minLines: 8,
            maxLines: 14,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: '编辑转写内容',
              alignLabelWithHint: true,
            ),
          )
        else
          _TranscriptPreview(source: _controller.text),
        if (!_isEditing || _isPreviewing) ...[
          const SizedBox(height: 4),
          ResearchDocumentActions(
            label: '转写',
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

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _isPreviewing = false;
    });
  }

  void _showEditor() => setState(() => _isPreviewing = false);

  void _showPreview() => setState(() => _isPreviewing = true);

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
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

class _TranscriptPreview extends StatelessWidget {
  const _TranscriptPreview({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(source),
    );
  }
}
