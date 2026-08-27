import 'package:aipin/features/research_beta/presentation/research_markdown_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'renders supported Markdown syntax as readable document content',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ResearchMarkdownPreview(
              source: '''# 标题
## 二级标题
- 无序项
1. 有序项
- [ ] 待办项
> 引用内容
---
**加粗** *斜体* <u>下划线</u> [资料](https://example.com)''',
            ),
          ),
        ),
      );

      expect(find.text('# 标题'), findsNothing);
      expect(find.text('标题'), findsOneWidget);
      expect(find.text('二级标题'), findsOneWidget);
      expect(find.text('无序项'), findsOneWidget);
      expect(find.text('1. 有序项'), findsNothing);
      expect(find.text('有序项'), findsOneWidget);
      expect(find.text('- [ ] 待办项'), findsNothing);
      expect(find.text('待办项'), findsOneWidget);
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
      expect(find.text('> 引用内容'), findsNothing);
      expect(
        find.byKey(const ValueKey('research-markdown-quote')),
        findsOneWidget,
      );
      expect(find.byType(Divider), findsOneWidget);
      expect(
        find.text('**加粗** *斜体* <u>下划线</u> [资料](https://example.com)'),
        findsNothing,
      );
      final inlineTextFinder = find.text('加粗 斜体 下划线 资料', findRichText: true);
      expect(inlineTextFinder, findsOneWidget);
      final richText = tester.widget<RichText>(inlineTextFinder);
      final root = richText.text as TextSpan;
      final document = root.children!.single as TextSpan;
      final spans = document.children!.cast<TextSpan>().toList();
      TextSpan spanFor(String text) =>
          spans.singleWhere((span) => span.text == text);

      expect(root.toPlainText(), '加粗 斜体 下划线 资料');
      expect(spanFor('加粗').style!.fontWeight, FontWeight.w600);
      expect(spanFor('斜体').style!.fontStyle, FontStyle.italic);
      expect(spanFor('下划线').style!.decoration, TextDecoration.underline);
      expect(
        spanFor('资料').style!.color,
        Theme.of(tester.element(inlineTextFinder)).colorScheme.primary,
      );
    },
  );
}
