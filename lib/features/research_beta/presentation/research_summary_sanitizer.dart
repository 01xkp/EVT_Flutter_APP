const _discardedSummaryFields = <String>{
  'entry_id',
  'evidence',
  'time_state',
  'title',
  'tag',
  'tags',
};

final _legacyFieldLine = RegExp(
  r'^(\s*)-\s+\*\*([a-z_]+)\*\*\s*$',
  caseSensitive: false,
);

const _voiceContentWrappers = <String>{
  'text',
  'content',
  'summary',
  'description',
};

const _legacySectionHeadings = <String>{'概览', '决策', '待办', '待确认', '知识要点'};

/// Hides diagnostic fields embedded in Markdown created by earlier clients.
///
/// The cleaned text is intentionally display-only. It becomes persistent only
/// when the user edits it and explicitly saves the summary.
String sanitizeLegacyAiSummaryMarkdown(String source) {
  final sourceLines = source.split('\n');
  final sanitizedLines = <String>[];
  var index = 0;

  while (index < sourceLines.length) {
    final line = sourceLines[index];
    if (_isLegacySectionHeading(line)) {
      index += 1;
      continue;
    }
    final match = _legacyFieldLine.firstMatch(line);
    final field = match?.group(2)?.toLowerCase();
    if (match == null || field == null) {
      sanitizedLines.add(line);
      index += 1;
      continue;
    }

    final fieldIndent = match.group(1)!.length;
    if (_voiceContentWrappers.contains(field)) {
      index += 1;
      while (index < sourceLines.length) {
        final descendant = sourceLines[index];
        if (descendant.trim().isEmpty) {
          sanitizedLines.add(descendant);
          index += 1;
          continue;
        }
        if (_leadingIndent(descendant) <= fieldIndent) {
          break;
        }
        sanitizedLines.add(_removeIndent(descendant, fieldIndent + 2));
        index += 1;
      }
      continue;
    }
    if (!_discardedSummaryFields.contains(field)) {
      sanitizedLines.add(line);
      index += 1;
      continue;
    }

    index += 1;
    while (index < sourceLines.length) {
      final descendant = sourceLines[index];
      if (descendant.trim().isEmpty ||
          _leadingIndent(descendant) > fieldIndent) {
        index += 1;
        continue;
      }
      break;
    }
  }

  while (sanitizedLines.isNotEmpty && sanitizedLines.first.trim().isEmpty) {
    sanitizedLines.removeAt(0);
  }
  while (sanitizedLines.isNotEmpty && sanitizedLines.last.trim().isEmpty) {
    sanitizedLines.removeLast();
  }
  return sanitizedLines.join('\n');
}

int _leadingIndent(String value) => value.length - value.trimLeft().length;

String _removeIndent(String value, int count) {
  var start = 0;
  while (start < value.length && start < count && value[start] == ' ') {
    start += 1;
  }
  return value.substring(start);
}

bool _isLegacySectionHeading(String value) {
  final heading = RegExp(r'^#{1,3}\s+(.+)$').firstMatch(value.trim());
  return heading != null && _legacySectionHeadings.contains(heading.group(1));
}
