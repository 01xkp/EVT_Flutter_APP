import 'package:flutter/material.dart';

class ResearchMarkdownPreview extends StatelessWidget {
  const ResearchMarkdownPreview({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in source.split('\n'))
            _MarkdownPreviewLine(line: line),
        ],
      ),
    );
  }
}

class _MarkdownPreviewLine extends StatelessWidget {
  const _MarkdownPreviewLine({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = RegExp(r'^(#{1,2})\s+(.+)$').firstMatch(line);
    if (heading != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _MarkdownInlineText(
          source: heading.group(2)!,
          style: heading.group(1)!.length == 1
              ? theme.textTheme.titleLarge
              : theme.textTheme.titleMedium,
        ),
      );
    }

    if (line.trim() == '---') {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Divider(),
      );
    }

    final checklist = RegExp(r'^(\s*)-\s+\[([ xX])\]\s+(.+)$').firstMatch(line);
    if (checklist != null) {
      final checked = checklist.group(2)!.toLowerCase() == 'x';
      return Padding(
        padding: EdgeInsets.only(
          left: (checklist.group(1)!.length ~/ 2) * 16,
          bottom: 4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              checked
                  ? Icons.check_box_outlined
                  : Icons.check_box_outline_blank,
              size: 18,
            ),
            const SizedBox(width: 6),
            Expanded(child: _MarkdownInlineText(source: checklist.group(3)!)),
          ],
        ),
      );
    }

    final quote = RegExp(r'^\s*>\s?(.*)$').firstMatch(line);
    if (quote != null) {
      return Container(
        key: const ValueKey('research-markdown-quote'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.colorScheme.outlineVariant, width: 2),
          ),
        ),
        child: _MarkdownInlineText(
          source: quote.group(1)!,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final ordered = RegExp(r'^(\s*)(\d+)\.\s+(.+)$').firstMatch(line);
    if (ordered != null) {
      return _ListLine(
        indent: ordered.group(1)!.length,
        marker: '${ordered.group(2)}.',
        content: ordered.group(3)!,
      );
    }

    final bullet = RegExp(r'^(\s*)-\s+(.+)$').firstMatch(line);
    if (bullet != null) {
      return _ListLine(
        indent: bullet.group(1)!.length,
        marker: '•',
        content: bullet.group(2)!,
      );
    }

    if (line.isEmpty) {
      return const SizedBox(height: 4);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _MarkdownInlineText(source: line),
    );
  }
}

class _ListLine extends StatelessWidget {
  const _ListLine({
    required this.indent,
    required this.marker,
    required this.content,
  });

  final int indent;
  final String marker;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: (indent ~/ 2) * 16, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 20, child: Text(marker)),
          Expanded(child: _MarkdownInlineText(source: content)),
        ],
      ),
    );
  }
}

class _MarkdownInlineText extends StatelessWidget {
  const _MarkdownInlineText({required this.source, this.style});

  final String source;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final pattern = RegExp(
      r'(\*\*(.+?)\*\*|\*(.+?)\*|<u>(.+?)</u>|\[([^\]]+)\]\(([^)]+)\))',
    );
    if (!pattern.hasMatch(source)) {
      return Text(source, style: style);
    }

    final theme = Theme.of(context);
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in pattern.allMatches(source)) {
      if (match.start > offset) {
        spans.add(TextSpan(text: source.substring(offset, match.start)));
      }
      if (match.group(2) != null) {
        spans.add(
          TextSpan(
            text: match.group(2),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
      } else if (match.group(3) != null) {
        spans.add(
          TextSpan(
            text: match.group(3),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      } else if (match.group(4) != null) {
        spans.add(
          TextSpan(
            text: match.group(4),
            style: const TextStyle(decoration: TextDecoration.underline),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: match.group(5),
            style: TextStyle(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        );
      }
      offset = match.end;
    }
    if (offset < source.length) {
      spans.add(TextSpan(text: source.substring(offset)));
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }
}
