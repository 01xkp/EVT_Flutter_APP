import 'package:flutter/material.dart';

class ResearchEditorModeToggle extends StatelessWidget {
  const ResearchEditorModeToggle({
    super.key,
    required this.label,
    required this.isEditing,
    required this.isPreviewing,
    required this.isSaving,
    required this.onStartEditing,
    required this.onShowEditor,
    required this.onShowPreview,
  });

  final String label;
  final bool isEditing;
  final bool isPreviewing;
  final bool isSaving;
  final VoidCallback onStartEditing;
  final VoidCallback onShowEditor;
  final VoidCallback onShowPreview;

  @override
  Widget build(BuildContext context) {
    final showsEditIcon = !isEditing || isPreviewing;
    return IconButton(
      tooltip: showsEditIcon ? '编辑$label' : '查看$label',
      onPressed: isSaving
          ? null
          : showsEditIcon
          ? (isEditing ? onShowEditor : onStartEditing)
          : onShowPreview,
      icon: Icon(
        showsEditIcon ? Icons.edit_outlined : Icons.visibility_outlined,
      ),
    );
  }
}
