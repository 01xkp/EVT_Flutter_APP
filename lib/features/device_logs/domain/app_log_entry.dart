class AppLogEntry {
  const AppLogEntry({
    required this.timestamp,
    required this.scope,
    required this.event,
    this.fields = const {},
  });

  final DateTime timestamp;
  final String scope;
  final String event;
  final Map<String, Object?> fields;

  String formatLine() {
    final details = fields.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    return '[AIPIN][$scope] ${timestamp.toIso8601String()} $event'
        '${details.isEmpty ? '' : ' $details'}';
  }
}
