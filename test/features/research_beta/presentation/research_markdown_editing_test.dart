import 'package:aipin/features/research_beta/presentation/research_markdown_editing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adds, replaces, and removes heading prefixes at the current line', () {
    const value = TextEditingValue(
      text: '事项',
      selection: TextSelection.collapsed(offset: 0),
    );

    final h1 = ResearchMarkdownEditing.applyLinePrefix(
      value,
      ResearchMarkdownEditing.headingOnePrefix,
    );
    final h2 = ResearchMarkdownEditing.applyLinePrefix(
      h1,
      ResearchMarkdownEditing.headingTwoPrefix,
    );
    final removed = ResearchMarkdownEditing.applyLinePrefix(
      h2,
      ResearchMarkdownEditing.headingTwoPrefix,
    );

    expect(h1.text, '# 事项');
    expect(h2.text, '## 事项');
    expect(removed.text, '事项');
  });

  test('toggles line prefixes and preserves the selected line text', () {
    const value = TextEditingValue(
      text: '第一项\n第二项',
      selection: TextSelection(baseOffset: 0, extentOffset: 7),
    );

    final checklist = ResearchMarkdownEditing.applyLinePrefix(
      value,
      ResearchMarkdownEditing.checklistPrefix,
    );
    final removed = ResearchMarkdownEditing.applyLinePrefix(
      checklist,
      ResearchMarkdownEditing.checklistPrefix,
    );

    expect(checklist.text, '- [ ] 第一项\n- [ ] 第二项');
    expect(removed.text, value.text);
  });

  test('toggles every supported list and quote line prefix', () {
    for (final prefix in <String>[
      ResearchMarkdownEditing.unorderedListPrefix,
      ResearchMarkdownEditing.orderedListPrefix,
      ResearchMarkdownEditing.quotePrefix,
    ]) {
      const value = TextEditingValue(
        text: '事项',
        selection: TextSelection.collapsed(offset: 0),
      );
      final formatted = ResearchMarkdownEditing.applyLinePrefix(value, prefix);
      final removed = ResearchMarkdownEditing.applyLinePrefix(
        formatted,
        prefix,
      );

      expect(formatted.text, '$prefix事项');
      expect(removed.text, '事项');
    }
  });

  test('wraps a selection or inserts a replaceable inline placeholder', () {
    const selected = TextEditingValue(
      text: '事项',
      selection: TextSelection(baseOffset: 0, extentOffset: 2),
    );
    const empty = TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
    );

    final bold = ResearchMarkdownEditing.applyInline(
      selected,
      marker: ResearchMarkdownEditing.boldMarker,
      placeholder: '加粗文字',
    );
    final underline = ResearchMarkdownEditing.applyInline(
      empty,
      marker: ResearchMarkdownEditing.underlineMarker,
      closingMarker: ResearchMarkdownEditing.underlineClosingMarker,
      placeholder: '下划线文字',
    );

    expect(bold.text, '**事项**');
    expect(underline.text, '<u>下划线文字</u>');
    expect(
      underline.selection,
      const TextSelection(baseOffset: 3, extentOffset: 8),
    );
  });

  test(
    'inserts a divider and Markdown links without losing surrounding text',
    () {
      const dividerValue = TextEditingValue(
        text: '上文下文',
        selection: TextSelection.collapsed(offset: 2),
      );
      const linkValue = TextEditingValue(
        text: '资料',
        selection: TextSelection(baseOffset: 0, extentOffset: 2),
      );

      final divider = ResearchMarkdownEditing.insertDivider(dividerValue);
      final link = ResearchMarkdownEditing.insertLink(
        linkValue,
        url: 'https://example.com',
        fallbackLabel: '链接文字',
      );

      expect(divider.text, '上文\n\n---\n\n下文');
      expect(link.text, '[资料](https://example.com)');
    },
  );

  test('keeps a reverse selection direction after inline formatting', () {
    const value = TextEditingValue(
      text: '事项',
      selection: TextSelection(baseOffset: 2, extentOffset: 0),
    );

    final updated = ResearchMarkdownEditing.applyInline(
      value,
      marker: ResearchMarkdownEditing.boldMarker,
      placeholder: '加粗文字',
    );

    expect(updated.text, '**事项**');
    expect(
      updated.selection,
      const TextSelection(baseOffset: 4, extentOffset: 2),
    );
  });
}
