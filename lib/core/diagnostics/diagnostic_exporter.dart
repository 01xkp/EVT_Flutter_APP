import 'dart:convert';

import 'package:evt_ble_app/core/diagnostics/evt_failure.dart';
import 'package:evt_ble_app/features/device_session/domain/device_snapshot.dart';

class DiagnosticExporter {
  String format({required EvtFailure failure, DeviceSnapshot? lastSnapshot}) {
    return const JsonEncoder.withIndent('  ').convert({
      'failureKind': failure.kind.name,
      'message': failure.message,
      'detail': failure.detail,
      'occurredAt': failure.occurredAt.toIso8601String(),
      'lastValidSnapshotAt': lastSnapshot?.observedAt.toIso8601String(),
      'lastValidSnapshotSource': lastSnapshot?.source,
    });
  }
}
