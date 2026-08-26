class AiVoiceServiceConfiguration {
  const AiVoiceServiceConfiguration._();

  static const dartDefineKey = 'ASR_API_BASE_URL';

  static const _dartDefineValue = String.fromEnvironment(dartDefineKey);

  static String resolveBaseUrl({
    String? explicitValue,
    String dartDefineValue = _dartDefineValue,
    String debugFallbackValue = '',
  }) {
    final explicit = explicitValue?.trim();
    if (explicit != null) {
      return explicit;
    }
    final defined = dartDefineValue.trim();
    if (defined.isNotEmpty) {
      return defined;
    }
    return debugFallbackValue.trim();
  }
}
