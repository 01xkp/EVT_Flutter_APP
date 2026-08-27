import 'package:aipin/core/design_system/widgets/ai_processing_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders a transcription notice at the top center', (
    tester,
  ) async {
    final controller = AiProcessingToastController();
    await tester.pumpWidget(_host(controller));

    controller.showProcessing(
      taskId: 'capture-1',
      stage: AiProcessingToastStage.transcribing,
    );
    await tester.pump();

    final toast = find.byKey(const ValueKey('ai-processing-toast'));
    expect(toast, findsOneWidget);
    expect(find.text('正在转写'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.getTopLeft(toast).dy, greaterThanOrEqualTo(12));

    controller.showProcessing(
      taskId: 'capture-1',
      stage: AiProcessingToastStage.summarizing,
    );
    await tester.pump();
    expect(find.text('正在总结'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('shows completed tasks one at a time for two seconds', (
    tester,
  ) async {
    final controller = AiProcessingToastController();
    await tester.pumpWidget(_host(controller));

    controller.complete(
      taskId: 'capture-1',
      completedAt: DateTime(2026, 8, 25, 10, 56),
      recordingName: '客户访谈',
      completionLabel: '转写完成',
    );
    controller.complete(
      taskId: 'capture-2',
      completedAt: DateTime(2026, 8, 25, 10, 57),
      recordingName: '产品复盘',
    );
    await tester.pump();
    expect(find.text('客户访谈 转写完成'), findsOneWidget);
    expect(find.text('产品复盘 完成'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('客户访谈 转写完成'), findsNothing);
    expect(find.text('产品复盘 完成'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('ellipsizes a long recording name in a single line', (
    tester,
  ) async {
    final controller = AiProcessingToastController();
    const recordingName = '这是一条用于验证顶部处理提示在较窄设备上不会换行或溢出的超长录音名称';
    await tester.pumpWidget(_host(controller));

    controller.complete(
      taskId: 'capture-1',
      completedAt: DateTime(2026, 8, 25, 10, 56),
      recordingName: recordingName,
      completionLabel: '转写完成',
    );
    await tester.pump();

    final label = tester.widget<Text>(
      find.text('$recordingName 转写完成'),
    );
    expect(label.maxLines, 1);
    expect(label.overflow, TextOverflow.ellipsis);
    controller.dispose();
  });

  testWidgets('shows a summary failure after ending an active task', (
    tester,
  ) async {
    final controller = AiProcessingToastController();
    await tester.pumpWidget(_host(controller));

    controller.showProcessing(
      taskId: 'capture-1',
      stage: AiProcessingToastStage.summarizing,
    );
    await tester.pump();
    expect(find.text('正在总结'), findsOneWidget);

    controller.dismiss('capture-1');
    await tester.pump();

    expect(find.text('AI 总结失败'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    controller.dispose();
  });

  testWidgets('shows a supplied failure when no processing stage remains', (
    tester,
  ) async {
    final controller = AiProcessingToastController();
    await tester.pumpWidget(_host(controller));

    controller.dismiss('capture-1', failureLabel: 'AI 总结失败');
    await tester.pump();

    expect(find.text('AI 总结失败'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    controller.dispose();
  });

  testWidgets('resumes a paused completion notice without dropping it', (
    tester,
  ) async {
    final controller = AiProcessingToastController();
    await tester.pumpWidget(_host(controller));

    controller.complete(
      taskId: 'capture-1',
      completedAt: DateTime(2026, 8, 25, 10, 56),
      recordingName: 'AI 语音',
    );
    controller.setPresentationEnabled(false);
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-processing-toast')), findsNothing);

    controller.setPresentationEnabled(true);
    await tester.pump();
    expect(find.text('AI 语音 完成'), findsOneWidget);
    controller.dispose();
  });
}

Widget _host(AiProcessingToastController controller) => MaterialApp(
  home: Stack(
    children: [
      const Scaffold(body: SizedBox.expand()),
      AiProcessingToastHost(controller: controller),
    ],
  ),
);
