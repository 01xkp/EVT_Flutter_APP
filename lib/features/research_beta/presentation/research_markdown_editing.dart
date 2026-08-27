import 'package:flutter/services.dart';

abstract final class ResearchMarkdownEditing {
  static const headingOnePrefix = '# ';
  static const headingTwoPrefix = '## ';
  static const unorderedListPrefix = '- ';
  static const orderedListPrefix = '1. ';
  static const checklistPrefix = '- [ ] ';
  static const quotePrefix = '> ';
  static const boldMarker = '**';
  static const italicMarker = '*';
  static const underlineMarker = '<u>';
  static const underlineClosingMarker = '</u>';

  static TextEditingValue applyLinePrefix(
    TextEditingValue value,
    String prefix,
  ) {
    final selection = _normalizedSelection(value);
    final range = _lineRange(value.text, selection);
    final originalLines = value.text
        .substring(range.start, range.end)
        .split('\n');
    final changes = <_LinePrefixChange>[];
    final updatedLines = <String>[];
    var lineOffset = range.start;

    for (final line in originalLines) {
      final update = _updateLinePrefix(line, prefix);
      changes.add(
        _LinePrefixChange(
          start: lineOffset,
          removedLength: update.removedLength,
          insertedLength: update.insertedLength,
        ),
      );
      updatedLines.add(update.text);
      lineOffset += line.length + 1;
    }

    final updatedText =
        '${value.text.substring(0, range.start)}'
        '${updatedLines.join('\n')}'
        '${value.text.substring(range.end)}';
    return TextEditingValue(
      text: updatedText,
      selection: TextSelection(
        baseOffset: _adjustOffset(selection.baseOffset, changes),
        extentOffset: _adjustOffset(selection.extentOffset, changes),
        isDirectional: selection.isDirectional,
      ),
    );
  }

  static TextEditingValue applyInline(
    TextEditingValue value, {
    required String marker,
    String? closingMarker,
    required String placeholder,
  }) {
    final selection = _normalizedSelection(value);
    final start = selection.start;
    final end = selection.end;
    final selected = value.text.substring(start, end);
    final content = selected.isEmpty ? placeholder : selected;
    final closing = closingMarker ?? marker;
    final updatedText =
        '${value.text.substring(0, start)}'
        '$marker$content$closing'
        '${value.text.substring(end)}';
    final contentStart = start + marker.length;
    return TextEditingValue(
      text: updatedText,
      selection: TextSelection(
        baseOffset: selection.isReversed
            ? contentStart + content.length
            : contentStart,
        extentOffset: selection.isReversed
            ? contentStart
            : contentStart + content.length,
        isDirectional: selection.isDirectional,
      ),
    );
  }

  static TextEditingValue insertDivider(TextEditingValue value) {
    final selection = _normalizedSelection(value);
    const divider = '\n\n---\n\n';
    final updatedText =
        '${value.text.substring(0, selection.start)}'
        '$divider'
        '${value.text.substring(selection.end)}';
    return TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(
        offset: selection.start + divider.length,
      ),
    );
  }

  static TextEditingValue insertLink(
    TextEditingValue value, {
    required String url,
    required String fallbackLabel,
  }) {
    final selection = _normalizedSelection(value);
    final selected = value.text.substring(selection.start, selection.end);
    final label = selected.isEmpty ? fallbackLabel : selected;
    final replacement = '[$label]($url)';
    final updatedText =
        '${value.text.substring(0, selection.start)}'
        '$replacement'
        '${value.text.substring(selection.end)}';
    return TextEditingValue(
      text: updatedText,
      selection: TextSelection(
        baseOffset: selection.isReversed
            ? selection.start + 1 + label.length
            : selection.start + 1,
        extentOffset: selection.isReversed
            ? selection.start + 1
            : selection.start + 1 + label.length,
        isDirectional: selection.isDirectional,
      ),
    );
  }

  static _LinePrefixUpdate _updateLinePrefix(String line, String prefix) {
    final heading = RegExp(r'^#{1,2}\s+').firstMatch(line);
    final isHeadingPrefix =
        prefix == headingOnePrefix || prefix == headingTwoPrefix;
    if (isHeadingPrefix && heading != null) {
      final currentPrefix = heading.group(0)!;
      if (currentPrefix == prefix) {
        return _LinePrefixUpdate(
          text: line.substring(currentPrefix.length),
          removedLength: currentPrefix.length,
        );
      }
      return _LinePrefixUpdate(
        text: '$prefix${line.substring(currentPrefix.length)}',
        removedLength: currentPrefix.length,
        insertedLength: prefix.length,
      );
    }
    if (line.startsWith(prefix)) {
      return _LinePrefixUpdate(
        text: line.substring(prefix.length),
        removedLength: prefix.length,
      );
    }
    return _LinePrefixUpdate(
      text: '$prefix$line',
      insertedLength: prefix.length,
    );
  }

  static _SelectionRange _normalizedSelection(TextEditingValue value) {
    final textLength = value.text.length;
    return _SelectionRange(
      baseOffset: value.selection.baseOffset.clamp(0, textLength),
      extentOffset: value.selection.extentOffset.clamp(0, textLength),
      isDirectional: value.selection.isDirectional,
    );
  }

  static _TextRange _lineRange(String text, _SelectionRange selection) {
    final start = selection.start;
    final lineStart = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
    final anchor = selection.isCollapsed
        ? selection.end
        : (selection.end - 1).clamp(0, text.length);
    final nextLine = text.indexOf('\n', anchor);
    return _TextRange(
      start: lineStart,
      end: nextLine == -1 ? text.length : nextLine,
    );
  }

  static int _adjustOffset(int offset, List<_LinePrefixChange> changes) {
    var delta = 0;
    for (final change in changes) {
      if (offset < change.start) {
        break;
      }
      final updatedStart = change.start + delta;
      if (offset == change.start ||
          offset < change.start + change.removedLength) {
        return updatedStart + change.insertedLength;
      }
      delta += change.insertedLength - change.removedLength;
    }
    return offset + delta;
  }
}

class _TextRange {
  const _TextRange({required this.start, required this.end});

  final int start;
  final int end;
}

class _SelectionRange {
  const _SelectionRange({
    required this.baseOffset,
    required this.extentOffset,
    required this.isDirectional,
  });

  final int baseOffset;
  final int extentOffset;
  final bool isDirectional;

  int get start => baseOffset < extentOffset ? baseOffset : extentOffset;
  int get end => baseOffset < extentOffset ? extentOffset : baseOffset;
  bool get isCollapsed => baseOffset == extentOffset;
  bool get isReversed => baseOffset > extentOffset;
}

class _LinePrefixUpdate {
  const _LinePrefixUpdate({
    required this.text,
    this.removedLength = 0,
    this.insertedLength = 0,
  });

  final String text;
  final int removedLength;
  final int insertedLength;
}

class _LinePrefixChange {
  const _LinePrefixChange({
    required this.start,
    required this.removedLength,
    required this.insertedLength,
  });

  final int start;
  final int removedLength;
  final int insertedLength;
}
