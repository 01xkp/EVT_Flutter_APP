import 'package:aipin/features/research_beta/domain/temporary_asr_gateway.dart';

AsrGeneratedNote? mapAsrGeneratedNote(Map<String, Object?> note) {
  final content = _mapValue(note['content']);
  if (content == null) {
    return null;
  }

  final voiceContent = _voiceContentFor(content);
  if (voiceContent.isEmpty) {
    return null;
  }

  return AsrGeneratedNote(
    title: 'AI 总结',
    summary: voiceContent.join('\n\n'),
    tags: const <String>[],
  );
}

Map<String, Object?>? _mapValue(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map<String, Object?>((key, item) => MapEntry('$key', item));
}

const _metadataFieldNames = <String>{
  'entry_id',
  'evidence',
  'time_state',
  'title',
  'tag',
  'tags',
};

List<String> _voiceContentFor(Object? value) {
  return _voiceContentForValue(value, retainPlainText: true);
}

List<String> _voiceContentForValue(
  Object? value, {
  required bool retainPlainText,
}) {
  switch (value) {
    case String value:
      final text = value.trim();
      return text.isEmpty || !retainPlainText
          ? const <String>[]
          : <String>[text];
    case List value:
      return value
          .expand(
            (item) =>
                _voiceContentForValue(item, retainPlainText: retainPlainText),
          )
          .toList(growable: false);
    case Map value:
      final fields = _mapValue(value);
      if (fields == null) {
        return const <String>[];
      }
      final text = _voiceText(fields);
      if (text != null) {
        return <String>[text];
      }
      return fields.entries
          .where(
            (entry) => !_metadataFieldNames.contains(entry.key.toLowerCase()),
          )
          .expand(
            (entry) =>
                _voiceContentForValue(entry.value, retainPlainText: false),
          )
          .toList(growable: false);
    default:
      return const <String>[];
  }
}

String? _voiceText(Map<String, Object?> fields) =>
    _textValue(fields['text']) ??
    _textValue(fields['content']) ??
    _textValue(fields['summary']) ??
    _textValue(fields['description']);

String? _textValue(Object? value) {
  if (value is! String) {
    return null;
  }
  final text = value.trim();
  return text.isEmpty ? null : text;
}
