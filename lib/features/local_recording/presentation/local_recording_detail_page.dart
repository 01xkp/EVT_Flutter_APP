import 'dart:async';

import 'package:aipin/core/design_system/widgets/app_toast.dart';
import 'package:aipin/core/design_system/widgets/app_confirmation_sheet.dart';
import 'package:aipin/core/documents/document_file_name.dart';
import 'package:aipin/core/documents/text_document_exporter.dart';
import 'package:aipin/features/local_recording/domain/audio_player_port.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/domain/recording_file_store.dart';
import 'package:aipin/features/local_recording/presentation/audio_playback_panel.dart';
import 'package:aipin/features/research_beta/application/research_capture_library_controller.dart';
import 'package:aipin/features/research_beta/application/research_capture_processing_controller.dart';
import 'package:aipin/features/research_beta/domain/research_capture.dart';
import 'package:aipin/features/research_beta/domain/research_capture_repository.dart';
import 'package:aipin/features/research_beta/presentation/research_capture_content.dart';
import 'package:aipin/features/research_beta/presentation/research_document_rename_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LocalRecordingDetailPage extends StatefulWidget {
  const LocalRecordingDetailPage({
    super.key,
    required this.recording,
    required this.localFiles,
    required this.audioPlayerFactory,
    required this.researchRepository,
    required this.researchLibrary,
    required this.researchProcessing,
    required this.onRequestAiProcessing,
    this.textDocumentExporter = const AppTextDocumentExporter(),
    this.recordings = const <LocalRecording>[],
    this.onOpenRecording,
  });

  final LocalRecording recording;
  final RecordingFileStore localFiles;
  final AudioPlayerPort Function() audioPlayerFactory;
  final ResearchCaptureRepository researchRepository;
  final ResearchCaptureLibraryController researchLibrary;
  final ResearchCaptureProcessingController researchProcessing;
  final Future<ResearchCapture?> Function(LocalRecording recording)
  onRequestAiProcessing;
  final TextDocumentExporter textDocumentExporter;
  final List<LocalRecording> recordings;
  final ValueChanged<LocalRecording>? onOpenRecording;

  @override
  State<LocalRecordingDetailPage> createState() =>
      _LocalRecordingDetailPageState();
}

enum _LocalRecordingDetailTab { playback, transcript, summary }

class _LocalRecordingDetailPageState extends State<LocalRecordingDetailPage> {
  var _tab = _LocalRecordingDetailTab.playback;
  var _isRequestingAi = false;
  ResearchCapture? _currentCapture;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ResearchCapture>>(
      stream: widget.researchRepository.watchAll(),
      initialData: const <ResearchCapture>[],
      builder: (context, snapshot) {
        final capture = _linkedCapture(snapshot.data ?? const []);
        _currentCapture = capture;
        return Scaffold(
          appBar: AppBar(title: Text(widget.recording.title)),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: SegmentedButton<_LocalRecordingDetailTab>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: _LocalRecordingDetailTab.playback,
                      label: Text('播放'),
                    ),
                    ButtonSegment(
                      value: _LocalRecordingDetailTab.transcript,
                      label: Text('转写'),
                    ),
                    ButtonSegment(
                      value: _LocalRecordingDetailTab.summary,
                      label: Text('总结'),
                    ),
                  ],
                  selected: {_tab},
                  onSelectionChanged: _selectTab,
                ),
              ),
              Expanded(child: _tabBody(capture)),
            ],
          ),
        );
      },
    );
  }

  Widget _tabBody(ResearchCapture? capture) => switch (_tab) {
    _LocalRecordingDetailTab.playback => _playback(),
    _LocalRecordingDetailTab.transcript => _transcript(capture),
    _LocalRecordingDetailTab.summary => _summary(capture),
  };

  Widget _playback() {
    final duration = widget.recording.duration;
    if (!widget.recording.isPlayable || duration == null) {
      return const Center(child: Text('这条录音暂时无法播放。'));
    }
    return AudioPlaybackPanel(
      duration: duration,
      resolvePath: () =>
          widget.localFiles.absolutePathFor(widget.recording.relativePath),
      audioPlayerFactory: widget.audioPlayerFactory,
      playbackErrorMessage: '本机录音暂时无法播放。',
      progressKey: const ValueKey('local-recording-playback-progress'),
      waveformKey: const ValueKey('local-recording-playback-waveform'),
      onPrevious: _previousRecording == null || widget.onOpenRecording == null
          ? null
          : () => widget.onOpenRecording!(_previousRecording!),
      onNext: _nextRecording == null || widget.onOpenRecording == null
          ? null
          : () => widget.onOpenRecording!(_nextRecording!),
    );
  }

  LocalRecording? get _previousRecording {
    final index = _recordingIndex;
    return index > 0 ? widget.recordings[index - 1] : null;
  }

  LocalRecording? get _nextRecording {
    final index = _recordingIndex;
    return index >= 0 && index + 1 < widget.recordings.length
        ? widget.recordings[index + 1]
        : null;
  }

  int get _recordingIndex => widget.recordings.indexWhere(
    (recording) => recording.id == widget.recording.id,
  );

  Widget _transcript(ResearchCapture? capture) {
    if (capture == null) {
      return _AiProcessingPrompt(
        title: '尚未进行 AI 转写',
        description: '确认后会从本机录音生成转写和 AI 总结。',
        isLoading: _isRequestingAi,
        onStart: _requestAiProcessing,
      );
    }
    return ResearchCaptureTranscriptPanel(
      capture: capture,
      onSaveTranscript: (value) =>
          widget.researchLibrary.saveTranscript(capture, value),
      onRetry: () => _retryTranscript(capture),
      onRegenerate: () => _regenerateTranscript(capture),
      onRenameDocument: (type) => _renameDocument(capture, type),
      onCopy: _copyText,
      onExport: (value) => _exportDocument(
        content: value,
        fileName: _documentFileName(capture, ResearchDocumentType.transcript),
        mimeType: 'text/plain',
      ),
    );
  }

  Widget _summary(ResearchCapture? capture) {
    if (capture == null) {
      return _AiProcessingPrompt(
        title: '尚未进行 AI 总结',
        description: '确认后会先转写录音，再生成可编辑的 Markdown 总结。',
        isLoading: _isRequestingAi,
        onStart: _requestAiProcessing,
      );
    }
    return ResearchCaptureSummaryPanel(
      capture: capture,
      onRetry: () => _retrySummary(capture),
      onRegenerate: () => _regenerateSummary(capture),
      onRenameDocument: (type) => _renameDocument(capture, type),
      onSaveMarkdownSummary: (value) =>
          widget.researchLibrary.saveMarkdownSummary(capture, value),
      onCopy: _copyText,
      onExport: (value) => _exportDocument(
        content: value,
        fileName: _documentFileName(capture, ResearchDocumentType.summary),
        mimeType: 'text/markdown',
      ),
    );
  }

  Future<void> _requestAiProcessing() async {
    if (_isRequestingAi ||
        _currentCapture != null ||
        !_canRequestAiProcessing) {
      return;
    }
    setState(() => _isRequestingAi = true);
    try {
      await widget.onRequestAiProcessing(widget.recording);
    } finally {
      if (mounted) {
        setState(() => _isRequestingAi = false);
      }
    }
  }

  Future<void> _retryTranscript(ResearchCapture capture) async {
    await widget.researchProcessing.retry(capture.id);
  }

  Future<void> _retrySummary(ResearchCapture capture) async {
    await widget.researchProcessing.regenerateSummary(capture.id);
  }

  Future<void> _regenerateTranscript(ResearchCapture capture) async {
    final confirmed = await AppConfirmationSheet.show(
      context,
      title: '重新生成转写？',
      message: '会重新上传原录音，并覆盖当前转写和 AI 总结。',
      confirmLabel: '重新生成',
    );
    if (confirmed) {
      await widget.researchProcessing.regenerateTranscript(capture.id);
    }
  }

  Future<void> _regenerateSummary(ResearchCapture capture) async {
    final confirmed = await AppConfirmationSheet.show(
      context,
      title: '重新生成总结？',
      message: '会基于当前转写重新生成并覆盖 AI 总结。',
      confirmLabel: '重新生成',
    );
    if (confirmed) {
      await widget.researchProcessing.regenerateSummary(capture.id);
    }
  }

  Future<void> _renameDocument(
    ResearchCapture capture,
    ResearchDocumentType type,
  ) async {
    final value = await ResearchDocumentRenameSheet.show(
      context,
      documentLabel: type.defaultTitle,
      initialTitle: capture.documentTitle(type),
    );
    if (value == null) {
      return;
    }
    try {
      await widget.researchLibrary.renameDocument(capture, type, value);
    } on ArgumentError {
      if (mounted) {
        AppToast.show(context, message: '请输入有效名称');
      }
    }
  }

  void _selectTab(Set<_LocalRecordingDetailTab> selection) {
    final next = selection.first;
    setState(() => _tab = next);
    if (next == _LocalRecordingDetailTab.playback || _currentCapture != null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _currentCapture == null) {
        unawaited(_requestAiProcessing());
      }
    });
  }

  Future<void> _copyText(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      AppToast.show(context, message: '文本已复制');
    }
  }

  Future<void> _exportDocument({
    required String content,
    required String fileName,
    required String mimeType,
  }) async {
    try {
      await widget.textDocumentExporter.export(
        fileName: fileName,
        content: content,
        mimeType: mimeType,
      );
      if (mounted) {
        AppToast.show(context, message: '已打开系统分享');
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, message: '导出失败，请重试');
      }
    }
  }

  String _documentFileName(ResearchCapture capture, ResearchDocumentType type) {
    final isTranscript = type == ResearchDocumentType.transcript;
    return DocumentFileName.build(
      customBaseName: isTranscript
          ? capture.transcriptTitle
          : capture.summaryTitle,
      fallbackTime: widget.recording.createdAt,
      fallbackSuffix: isTranscript ? '转写' : '总结',
      extension: isTranscript ? 'txt' : 'md',
    );
  }

  bool get _canRequestAiProcessing {
    final duration = widget.recording.duration;
    return widget.recording.isPlayable &&
        duration != null &&
        duration >= const Duration(seconds: 2);
  }

  ResearchCapture? _linkedCapture(List<ResearchCapture> captures) {
    for (final capture in captures) {
      if (capture.originalLocalRecordingId == widget.recording.id) {
        return capture;
      }
    }
    return null;
  }
}

class _AiProcessingPrompt extends StatelessWidget {
  const _AiProcessingPrompt({
    required this.title,
    required this.description,
    required this.isLoading,
    required this.onStart,
  });

  final String title;
  final String description;
  final bool isLoading;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome_outlined, size: 32),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: isLoading ? null : onStart,
              icon: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_outlined),
              label: const Text('开始 AI 转写和总结'),
            ),
          ],
        ),
      ),
    );
  }
}
