import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:flutter/material.dart';

abstract final class ResearchDocumentRenameSheet {
  static Future<String?> show(
    BuildContext context, {
    required String documentLabel,
    required String initialTitle,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ResearchDocumentRenameSheet(
        documentLabel: documentLabel,
        initialTitle: initialTitle,
      ),
    );
  }
}

class _ResearchDocumentRenameSheet extends StatefulWidget {
  const _ResearchDocumentRenameSheet({
    required this.documentLabel,
    required this.initialTitle,
  });

  final String documentLabel;
  final String initialTitle;

  @override
  State<_ResearchDocumentRenameSheet> createState() =>
      _ResearchDocumentRenameSheetState();
}

class _ResearchDocumentRenameSheetState
    extends State<_ResearchDocumentRenameSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _controller.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('重命名', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 60,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: canSave ? (_) => _save() : null,
              decoration: InputDecoration(
                labelText: '${widget.documentLabel} 名称',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            AppButton.primary(
              label: '保存',
              onPressed: canSave ? _save : null,
              icon: Icons.check_outlined,
            ),
          ],
        ),
      ),
    );
  }

  void _save() => Navigator.of(context).pop(_controller.text);
}
