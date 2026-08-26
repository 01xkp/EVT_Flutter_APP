import 'package:aipin/features/research_beta/presentation/research_upload_confirmation_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('asks whether to start AI transcription and summary', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => ResearchUploadConfirmationSheet.show(context),
            child: const Text('打开确认'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开确认'));
    await tester.pumpAndSettle();

    expect(find.text('使用 AI 转写和总结？'), findsOneWidget);
    expect(find.text('开始处理'), findsOneWidget);
    expect(find.text('暂不处理'), findsOneWidget);
  });
}
