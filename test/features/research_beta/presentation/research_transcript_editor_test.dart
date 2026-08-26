import 'package:aipin/features/research_beta/presentation/research_transcript_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows transcript read-only until its edit button is tapped', (
    tester,
  ) async {
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResearchTranscriptEditor(
            source: '机器转写内容',
            onSave: (value) async => saved = value,
          ),
        ),
      ),
    );

    expect(find.text('机器转写内容'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byTooltip('编辑转写'), findsOneWidget);

    await tester.tap(find.byTooltip('编辑转写'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('查看转写'), findsOneWidget);
    expect(find.byTooltip('编辑转写'), findsNothing);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '编辑后的转写');
    await tester.tap(find.byTooltip('查看转写'));
    await tester.pump();
    expect(find.text('编辑后的转写'), findsOneWidget);
    expect(find.byTooltip('编辑转写'), findsOneWidget);
    expect(find.byTooltip('查看转写'), findsNothing);
    expect(find.text('取消'), findsNothing);
    expect(find.text('保存'), findsNothing);
    expect(find.byTooltip('复制转写'), findsOneWidget);
    expect(find.byTooltip('导出转写'), findsOneWidget);

    await tester.tap(find.byTooltip('编辑转写'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(saved, '编辑后的转写');
  });
}
