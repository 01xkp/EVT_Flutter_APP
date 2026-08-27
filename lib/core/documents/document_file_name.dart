abstract final class DocumentFileName {
  static final RegExp _reservedCharacters = RegExp(r'[\\\\/:*?"<>|]');
  static final RegExp _controlCharacters = RegExp(r'[\u0000-\u001F\u007F]');
  static final RegExp _trailingUnsafeCharacters = RegExp(r'[. ]+$');
  static final RegExp _windowsDeviceName = RegExp(
    r'^(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$',
    caseSensitive: false,
  );

  static String? normalizeCustomBaseName(
    String? source, {
    String? matchingExtension,
  }) {
    if (source == null) {
      return null;
    }

    var normalized = source
        .replaceAll(_controlCharacters, '')
        .replaceAll(_reservedCharacters, '')
        .trim();
    normalized = normalized.replaceFirst(_trailingUnsafeCharacters, '').trim();
    final extension = matchingExtension?.trim().replaceFirst(
      RegExp(r'^\.'),
      '',
    );
    if (extension != null && extension.isNotEmpty) {
      final suffix = '.${extension.toLowerCase()}';
      if (normalized.toLowerCase().endsWith(suffix)) {
        normalized = normalized
            .substring(0, normalized.length - suffix.length)
            .trim();
      }
    } else {
      normalized = normalized
          .replaceFirst(RegExp(r'\.(?:txt|md)$', caseSensitive: false), '')
          .trim();
    }
    normalized = normalized.replaceFirst(_trailingUnsafeCharacters, '').trim();

    if (normalized.isEmpty || _windowsDeviceName.hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }

  static String build({
    required String? customBaseName,
    required DateTime fallbackTime,
    required String fallbackSuffix,
    required String extension,
  }) {
    final normalizedExtension = extension.trim().replaceFirst(
      RegExp(r'^\.'),
      '',
    );
    if (normalizedExtension.isEmpty) {
      throw ArgumentError.value(extension, 'extension', '文件扩展名不能为空。');
    }
    final customName = normalizeCustomBaseName(
      customBaseName,
      matchingExtension: normalizedExtension,
    );
    final baseName =
        customName ??
        '${_formatTimestamp(fallbackTime)}_${fallbackSuffix.trim()}';
    return '$baseName.$normalizedExtension';
  }

  static String _formatTimestamp(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}_'
      '${value.hour.toString().padLeft(2, '0')}'
      '${value.minute.toString().padLeft(2, '0')}'
      '${value.second.toString().padLeft(2, '0')}';
}
