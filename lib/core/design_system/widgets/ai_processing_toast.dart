import 'dart:async';
import 'dart:collection';

import 'package:aipin/core/design_system/evt_theme.dart';
import 'package:flutter/material.dart';

enum AiProcessingToastStage { transcribing, summarizing }

class AiProcessingToastController extends ChangeNotifier {
  final Map<String, AiProcessingToastStage> _processing =
      <String, AiProcessingToastStage>{};
  final Queue<DateTime> _pendingCompletions = Queue<DateTime>();
  DateTime? _activeCompletion;
  Timer? _completionTimer;
  var _presentationEnabled = true;

  AiProcessingToastDisplay? get display {
    if (!_presentationEnabled) {
      return null;
    }
    final completion = _activeCompletion;
    if (completion != null) {
      return AiProcessingToastDisplay.completed(completion);
    }
    if (_processing.values.contains(AiProcessingToastStage.transcribing)) {
      return const AiProcessingToastDisplay.processing(
        AiProcessingToastStage.transcribing,
      );
    }
    if (_processing.values.contains(AiProcessingToastStage.summarizing)) {
      return const AiProcessingToastDisplay.processing(
        AiProcessingToastStage.summarizing,
      );
    }
    return null;
  }

  void showProcessing({
    required String taskId,
    required AiProcessingToastStage stage,
  }) {
    _processing[taskId] = stage;
    notifyListeners();
  }

  void complete({required String taskId, required DateTime completedAt}) {
    _processing.remove(taskId);
    _pendingCompletions.add(completedAt);
    _startOrResumeCompletion();
    notifyListeners();
  }

  void setPresentationEnabled(bool value) {
    if (_presentationEnabled == value) {
      return;
    }
    _presentationEnabled = value;
    _completionTimer?.cancel();
    _completionTimer = null;
    if (value) {
      _startOrResumeCompletion();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _completionTimer?.cancel();
    super.dispose();
  }

  void _startOrResumeCompletion() {
    if (!_presentationEnabled) {
      return;
    }
    _activeCompletion ??= _pendingCompletions.isEmpty
        ? null
        : _pendingCompletions.removeFirst();
    if (_activeCompletion == null || _completionTimer != null) {
      return;
    }
    _completionTimer = Timer(const Duration(seconds: 2), () {
      _completionTimer = null;
      _activeCompletion = null;
      _startOrResumeCompletion();
      notifyListeners();
    });
  }
}

class AiProcessingToastDisplay {
  const AiProcessingToastDisplay.processing(this.stage) : completedAt = null;

  const AiProcessingToastDisplay.completed(this.completedAt) : stage = null;

  final AiProcessingToastStage? stage;
  final DateTime? completedAt;

  bool get isCompleted => completedAt != null;
}

class AiProcessingToastHost extends StatelessWidget {
  const AiProcessingToastHost({super.key, required this.controller});

  final AiProcessingToastController controller;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 12,
      left: 20,
      right: 20,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final display = controller.display;
          return Center(
            child: AnimatedSwitcher(
              duration: EvtTheme.motionDuration,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: display == null
                  ? const SizedBox(key: ValueKey('ai-processing-toast-hidden'))
                  : _AiProcessingToastView(display: display),
            ),
          );
        },
      ),
    );
  }
}

class _AiProcessingToastView extends StatelessWidget {
  const _AiProcessingToastView({required this.display});

  final AiProcessingToastDisplay display;

  @override
  Widget build(BuildContext context) {
    final isCompleted = display.isCompleted;
    final label = isCompleted
        ? _completionLabel(display.completedAt!)
        : switch (display.stage!) {
            AiProcessingToastStage.transcribing => '正在转写',
            AiProcessingToastStage.summarizing => '正在总结',
          };
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: Container(
            key: const ValueKey('ai-processing-toast'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color.fromRGBO(0, 0, 0, 0.76),
              borderRadius: BorderRadius.all(EvtTheme.componentRadius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isCompleted)
                  const Icon(
                    Icons.check_circle_outline,
                    color: Colors.white,
                    size: 18,
                  )
                else
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _completionLabel(DateTime completedAt) {
    final hour = completedAt.hour.toString().padLeft(2, '0');
    final minute = completedAt.minute.toString().padLeft(2, '0');
    return '${completedAt.month}-${completedAt.day} $hour:$minute 完成';
  }
}
