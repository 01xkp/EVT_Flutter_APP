import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:evt_ble_app/core/persistence/app_database.dart';
import 'package:evt_ble_app/features/evidence/domain/evidence_bundle.dart';
import 'package:evt_ble_app/features/evidence/domain/evidence_repository.dart';
import 'package:evt_ble_app/features/observation/domain/observation_verdict.dart';

class DriftEvidenceRepository implements EvidenceRepository {
  DriftEvidenceRepository(this._database);

  final AppDatabase _database;

  @override
  Future<void> save(EvidenceBundle bundle) async {
    if (bundle.isMock ||
        bundle.deviceId.trim().isEmpty ||
        bundle.deviceName.trim().isEmpty) {
      throw ArgumentError('证据必须来自具备真实设备身份的会话。');
    }
    await _database.transaction(() async {
      await _database
          .into(_database.evidenceBundles)
          .insert(
            EvidenceBundlesCompanion.insert(
              id: bundle.id,
              sessionId: bundle.sessionId,
              deviceId: bundle.deviceId,
              deviceName: bundle.deviceName,
              firmwareVersion: Value(bundle.firmwareVersion),
              verdict: bundle.verdict.name,
              reason: bundle.reason,
              manualNote: Value(bundle.manualNote),
              diagnosticJson: jsonEncode(bundle.diagnosticPayload),
              createdAt: bundle.createdAt,
            ),
          );
      await _database.batch((batch) {
        for (var index = 0; index < bundle.records.length; index += 1) {
          final record = bundle.records[index];
          batch.insert(
            _database.sessionEvents,
            SessionEventsCompanion.insert(
              bundleId: bundle.id,
              sequence: index,
              recordKind: record.kind.name,
              source: record.source,
              occurredAt: record.occurredAt,
              payloadJson: jsonEncode(record.data),
            ),
          );
        }
      });
    });
  }

  @override
  Future<EvidenceBundle?> byId(String id) async {
    final row = await (_database.select(
      _database.evidenceBundles,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    return row == null ? null : _hydrate(row);
  }

  @override
  Future<List<EvidenceBundle>> all() async {
    final rows = await (_database.select(
      _database.evidenceBundles,
    )..orderBy([(row) => OrderingTerm.desc(row.createdAt)])).get();
    return Future.wait(rows.map(_hydrate));
  }

  @override
  Future<void> delete(String id) async {
    await _database.transaction(() async {
      await (_database.delete(
        _database.sessionEvents,
      )..where((row) => row.bundleId.equals(id))).go();
      await (_database.delete(
        _database.evidenceBundles,
      )..where((row) => row.id.equals(id))).go();
    });
  }

  Future<EvidenceBundle> _hydrate(EvidenceBundleRow row) async {
    final records =
        await (_database.select(_database.sessionEvents)
              ..where((record) => record.bundleId.equals(row.id))
              ..orderBy([(record) => OrderingTerm.asc(record.sequence)]))
            .get();
    return EvidenceBundle(
      id: row.id,
      sessionId: row.sessionId,
      deviceId: row.deviceId,
      deviceName: row.deviceName,
      firmwareVersion: row.firmwareVersion,
      verdict: ObservationVerdict.values.byName(row.verdict),
      reason: row.reason,
      manualNote: row.manualNote,
      createdAt: row.createdAt,
      records: [
        for (final record in records)
          EvidenceSourceRecord(
            kind: EvidenceRecordKind.values.byName(record.recordKind),
            source: record.source,
            occurredAt: record.occurredAt,
            data: Map<String, Object?>.from(
              jsonDecode(record.payloadJson) as Map,
            ),
          ),
      ],
      diagnosticPayload: Map<String, Object?>.from(
        jsonDecode(row.diagnosticJson) as Map,
      ),
    );
  }
}
