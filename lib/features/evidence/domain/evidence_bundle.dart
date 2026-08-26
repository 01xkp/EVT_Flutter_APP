import 'package:aipin/features/observation/domain/observation_verdict.dart';

enum EvidenceRecordKind { snapshot, event, note }

class EvidenceSourceRecord {
  EvidenceSourceRecord({
    required this.kind,
    required this.source,
    required this.occurredAt,
    Map<String, Object?> data = const {},
  }) : data = Map.unmodifiable(data);

  final EvidenceRecordKind kind;
  final String source;
  final DateTime occurredAt;
  final Map<String, Object?> data;
}

class EvidenceBundle {
  EvidenceBundle({
    required this.id,
    required this.sessionId,
    required this.deviceId,
    required this.deviceName,
    required this.verdict,
    required this.reason,
    required this.createdAt,
    required List<EvidenceSourceRecord> records,
    this.firmwareVersion,
    this.manualNote,
    Map<String, Object?> diagnosticPayload = const {},
    this.isMock = false,
  }) : records = List.unmodifiable(records),
       diagnosticPayload = Map.unmodifiable(diagnosticPayload);

  factory EvidenceBundle.completed({
    required String deviceId,
    required String deviceName,
    required ObservationVerdict verdict,
    required String reason,
    String? firmwareVersion,
    String? sessionId,
    String? manualNote,
    List<EvidenceSourceRecord> records = const [],
    Map<String, Object?> diagnosticPayload = const {},
    bool isMock = false,
    DateTime? createdAt,
  }) {
    final timestamp = createdAt ?? DateTime.now();
    final id = '${timestamp.microsecondsSinceEpoch}-${deviceId.hashCode.abs()}';
    return EvidenceBundle(
      id: id,
      sessionId: sessionId ?? id,
      deviceId: deviceId,
      deviceName: deviceName,
      firmwareVersion: firmwareVersion,
      verdict: verdict,
      reason: reason,
      manualNote: manualNote,
      records: records,
      diagnosticPayload: diagnosticPayload,
      isMock: isMock,
      createdAt: timestamp,
    );
  }

  final String id;
  final String sessionId;
  final String deviceId;
  final String deviceName;
  final String? firmwareVersion;
  final ObservationVerdict verdict;
  final String reason;
  final String? manualNote;
  final DateTime createdAt;
  final List<EvidenceSourceRecord> records;
  final Map<String, Object?> diagnosticPayload;
  final bool isMock;
}
