import 'dart:async';

import 'package:aipin/features/research_beta/domain/research_capture.dart';
import 'package:aipin/features/research_beta/presentation/research_markdown_document_editor.dart';
import 'package:aipin/features/research_beta/presentation/research_summary_sanitizer.dart';
import 'package:aipin/features/research_beta/presentation/research_transcript_editor.dart';
import 'package:flutter/material.dart';

class ResearchCaptureTranscriptPanel extends StatelessWidget {
  const ResearchCaptureTranscriptPanel({
    super.key,
    required this.capture,
    required this.onSaveTranscript,
    required this.onRetry,
    this.onRegenerate,
    this.onRenameDocument,
    required this.onCopy,
    required this.onExport,
  });

  final ResearchCapture capture;
  final Future<void> Function(String value) onSaveTranscript;
  final Future<void> Function() onRetry;
  final Future<void> Function()? onRegenerate;
  final Future<void> Function(ResearchDocumentType type)? onRenameDocument;
  final Future<void> Function(String value) onCopy;
  final Future<void> Function(String value) onExport;

  @override
  Widget build(BuildContext context) {
    final capture = this.capture;
    final transcript = capture.rawTranscript;
    final failed =
        capture.processingState == ResearchProcessingState.uploadFailed ||
        capture.processingState == ResearchProcessingState.transcriptionFailed;
    if (transcript == null) {
      return _ResearchPendingPanel(
        label: failed ? capture.failureReason ?? '转写失败' : '正在转写',
        showLoader: !failed,
        retryLabel: failed ? '重试 AI 转写' : null,
        onRetry: failed ? onRetry : null,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      children: [
        ResearchTranscriptEditor(
          title: capture.documentTitle(ResearchDocumentType.transcript),
          source: transcript,
          onSave: onSaveTranscript,
          onRegenerate: capture.isTerminal ? onRegenerate : null,
          onRename: onRenameDocument == null
              ? null
              : () => onRenameDocument!(ResearchDocumentType.transcript),
          onCopy: onCopy,
          onExport: onExport,
        ),
      ],
    );
  }
}

class ResearchCaptureSummaryPanel extends StatelessWidget {
  const ResearchCaptureSummaryPanel({
    super.key,
    required this.capture,
    required this.onRetry,
    this.onRegenerate,
    this.onRenameDocument,
    required this.onSaveMarkdownSummary,
    required this.onCopy,
    required this.onExport,
  });

  final ResearchCapture capture;
  final Future<void> Function() onRetry;
  final Future<void> Function()? onRegenerate;
  final Future<void> Function(ResearchDocumentType type)? onRenameDocument;
  final Future<void> Function(String value) onSaveMarkdownSummary;
  final Future<void> Function(String value) onCopy;
  final Future<void> Function(String value) onExport;

  @override
  Widget build(BuildContext context) {
    final summary = capture.summary;
    if (summary == null) {
      final failed =
          capture.processingState == ResearchProcessingState.uploadFailed ||
          capture.processingState ==
              ResearchProcessingState.transcriptionFailed ||
          capture.processingState == ResearchProcessingState.summaryFailed;
      return _ResearchPendingPanel(
        label: failed ? capture.failureReason ?? 'AI 总结失败' : '正在总结',
        showLoader: !failed,
        retryLabel: failed ? '重试 AI 总结' : null,
        onRetry: failed ? onRetry : null,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      children: [
        ResearchMarkdownDocumentEditor(
          title: capture.documentTitle(ResearchDocumentType.summary),
          source: sanitizeLegacyAiSummaryMarkdown(summary),
          onSave: onSaveMarkdownSummary,
          onRegenerate: capture.isTerminal ? onRegenerate : null,
          onRename: onRenameDocument == null
              ? null
              : () => onRenameDocument!(ResearchDocumentType.summary),
          onCopy: onCopy,
          onExport: onExport,
        ),
      ],
    );
  }
}

class _ResearchPendingPanel extends StatelessWidget {
  const _ResearchPendingPanel({
    required this.label,
    this.showLoader = false,
    this.retryLabel,
    this.onRetry,
  });

  final String label;
  final bool showLoader;
  final String? retryLabel;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showLoader) ...[
              Semantics(
                label: label,
                liveRegion: true,
                child: SizedBox(
                  key: const ValueKey('researchProcessingLoader'),
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (retryLabel != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => unawaited(onRetry!()),
                icon: const Icon(Icons.refresh_outlined),
                label: Text(retryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
