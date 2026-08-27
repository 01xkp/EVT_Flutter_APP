import 'package:aipin/features/research_beta/presentation/research_markdown_document_editor.dart';
import 'package:aipin/features/research_beta/presentation/research_summary_sanitizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('formats Markdown and switches between editing and preview', (
    tester,
  ) async {
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResearchMarkdownDocumentEditor(
            source: '项目摘要',
            onSave: (value) async => saved = value,
          ),
        ),
      ),
    );

    expect(find.text('AI 总结'), findsOneWidget);
    expect(find.textContaining('Markdown'), findsNothing);
    await tester.tap(find.byTooltip('编辑总结'));
    await tester.pump();
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    await tester.tap(find.byTooltip('一级标题'));
    await tester.tap(find.byTooltip('查看总结'));
    await tester.pump();

    expect(find.text('项目摘要'), findsOneWidget);
    expect(find.byTooltip('编辑总结'), findsOneWidget);
    expect(find.byTooltip('查看总结'), findsNothing);
    expect(find.text('取消'), findsNothing);
    expect(find.text('保存'), findsNothing);
    expect(find.byTooltip('复制总结'), findsOneWidget);
    expect(find.byTooltip('导出总结'), findsOneWidget);
    await tester.tap(find.byTooltip('编辑总结'));
    await tester.pump();
    await tester.tap(find.text('保存'));

    expect(saved, '# 项目摘要');
  });

  testWidgets('renders second-level headings and bold text without syntax', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResearchMarkdownDocumentEditor(
            source: '## 概览\n- **重点**\n  - 正文',
            onSave: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('## 概览'), findsNothing);
    expect(find.text('概览'), findsOneWidget);
    expect(find.text('重点', findRichText: true), findsOneWidget);
    expect(find.text('正文'), findsOneWidget);
  });

  testWidgets('shows two formatting rows and saves a valid Markdown link', (
    tester,
  ) async {
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResearchMarkdownDocumentEditor(
            source: '',
            onSave: (value) async => saved = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('编辑总结'));
    await tester.pump();

    expect(find.byKey(const ValueKey('markdown-format-row-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('markdown-format-row-2')), findsOneWidget);
    for (final tooltip in <String>[
      '一级标题',
      '二级标题',
      '加粗',
      '斜体',
      '下划线',
      '无序列表',
      '有序列表',
      '待办项',
      '引用',
      '分割线',
      '插入链接',
    ]) {
      expect(find.byTooltip(tooltip), findsOneWidget);
    }

    await tester.tap(find.byTooltip('一级标题'));
    await tester.tap(find.byTooltip('斜体'));
    await tester.tap(find.byTooltip('待办项'));
    await tester.tap(find.byTooltip('引用'));
    await tester.tap(find.byTooltip('分割线'));
    await tester.tap(find.byTooltip('插入链接'));
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('markdown-link-url')),
      'https://example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('markdown-link-label')),
      '资料',
    );
    await tester.tap(find.text('插入'));
    await tester.pump();
    await tester.tap(find.text('保存'));

    expect(saved, contains('[资料](https://example.com)'));
  });

  testWidgets('keeps content unchanged when a link is cancelled or invalid', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResearchMarkdownDocumentEditor(
            source: '',
            onSave: (_) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('编辑总结'));
    await tester.pump();
    await tester.tap(find.byTooltip('插入链接'));
    await tester.pump();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('取消')),
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('markdown-summary-input')),
          )
          .controller!
          .text,
      isEmpty,
    );

    await tester.tap(find.byTooltip('插入链接'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('markdown-link-url')),
      'not-a-url',
    );
    await tester.tap(find.text('插入'));
    await tester.pump();
    expect(find.text('插入链接'), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('取消')),
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('markdown-summary-input')),
          )
          .controller!
          .text,
      isEmpty,
    );
  });

  test('removes internal fields from legacy AI summary Markdown', () {
    const legacySummary = '''## 概览

- **entry_id**
  - internal-id
- **title**
  - 项目回顾
- **tags**
  - 团队标签
- **text**
  - 确定上线时间。
- **evidence**
  - **text**
    - 原始依据文本。
  - **time_state**
    - no_time_evidence''';

    final result = sanitizeLegacyAiSummaryMarkdown(legacySummary);

    expect(result, isNot(contains('项目回顾')));
    expect(result, isNot(contains('tags')));
    expect(result, isNot(contains('团队标签')));
    expect(result, contains('确定上线时间。'));
    expect(result, isNot(contains('## 概览')));
    expect(result, isNot(contains('**text**')));
    expect(result, isNot(contains('entry_id')));
    expect(result, isNot(contains('internal-id')));
    expect(result, isNot(contains('evidence')));
    expect(result, isNot(contains('原始依据文本。')));
    expect(result, isNot(contains('time_state')));
    expect(result, isNot(contains('no_time_evidence')));
  });
}
