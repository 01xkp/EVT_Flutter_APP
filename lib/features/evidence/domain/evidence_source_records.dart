import 'package:aipin/core/protocol/device_event.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';
import 'package:aipin/features/evidence/domain/evidence_bundle.dart';

abstract final class EvidenceSourceRecords {
  static EvidenceSourceRecord snapshot(DeviceSnapshot snapshot) {
    return EvidenceSourceRecord(
      kind: EvidenceRecordKind.snapshot,
      source: snapshot.source,
      occurredAt: snapshot.observedAt,
      data: {
        'state': snapshot.state.name,
        'batteryPercent': snapshot.batteryPercent,
        'isCharging': snapshot.isCharging,
        'standbyPowerMilliwatts': snapshot.standbyPowerMilliwatts,
      },
    );
  }

  static EvidenceSourceRecord event(DeviceEvent event) {
    return EvidenceSourceRecord(
      kind: EvidenceRecordKind.event,
      source: event.source,
      occurredAt: event.occurredAt,
      data: {
        'kind': event.kind.name,
        'command': event.command,
        'payload': event.payload.toList(),
      },
    );
  }

  static EvidenceSourceRecord manualNote(String note) {
    return EvidenceSourceRecord(
      kind: EvidenceRecordKind.note,
      source: '人工观察',
      occurredAt: DateTime.now(),
      data: {'note': note},
    );
  }
}
