import 'package:flutter/material.dart';

class ResearchDocumentActions extends StatelessWidget {
  const ResearchDocumentActions({
    super.key,
    required this.label,
    required this.isProcessing,
    this.onCopy,
    this.onExport,
  });

  final String label;
  final bool isProcessing;
  final Future<void> Function()? onCopy;
  final Future<void> Function()? onExport;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '复制$label',
            onPressed: isProcessing || onCopy == null
                ? null
                : () => _run(onCopy!),
            icon: const Icon(Icons.copy_outlined),
          ),
          IconButton(
            tooltip: '导出$label',
            onPressed: isProcessing || onExport == null
                ? null
                : () => _run(onExport!),
            icon: const Icon(Icons.file_upload_outlined),
          ),
        ],
      ),
    );
  }

  void _run(Future<void> Function() action) {
    action();
  }
}
