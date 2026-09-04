import 'dart:convert';

import 'package:aipin/core/diagnostics/diagnostic_sanitizer.dart';
import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';

class DiagnosticExporter {
  String format({required EvtFailure failure, DeviceSnapshot? lastSnapshot}) {
    final fields = const DiagnosticSanitizer().sanitize(
      scope: 'STORAGE',
      fields: <String, Object?>{
        'error_type': failure.kind.name,
        'stage': 'export',
        'last_valid_snapshot_at': lastSnapshot?.observedAt.toIso8601String(),
        'last_valid_snapshot_source': lastSnapshot?.source,
      },
    );
    return const JsonEncoder.withIndent(
      '  ',
    ).convert({'occurredAt': failure.occurredAt.toIso8601String(), ...fields});
  }
}
