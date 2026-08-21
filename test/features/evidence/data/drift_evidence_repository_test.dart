import 'package:evt_ble_app/core/persistence/app_database.dart';
import 'package:evt_ble_app/features/evidence/data/drift_evidence_repository.dart';
import 'package:evt_ble_app/features/evidence/domain/evidence_bundle.dart';
import 'package:evt_ble_app/features/observation/domain/observation_verdict.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftEvidenceRepository repository;

  setUp(() {
    database = AppDatabase.forTesting();
    repository = DriftEvidenceRepository(database);
  });

  tearDown(() => database.close());

  test(
    'persists an immutable verdict with identity and source records',
    () async {
      final bundle = EvidenceBundle.completed(
        deviceId: '71:BF:E2:3B:84:23',
        deviceName: 'AIPIN_8423',
        firmwareVersion: 'V1.5',
        verdict: ObservationVerdict.unverifiable,
        reason: '待机功耗字段未上报',
        records: [
          EvidenceSourceRecord(
            kind: EvidenceRecordKind.snapshot,
            source: '首读 0x91',
            occurredAt: DateTime(2026, 8, 21, 10, 32),
            data: const {'batteryPercent': 80},
          ),
        ],
      );

      await repository.save(bundle);
      final saved = await repository.byId(bundle.id);

      expect(saved!.reason, '待机功耗字段未上报');
      expect(saved.deviceName, 'AIPIN_8423');
      expect(saved.records.single.source, '首读 0x91');
      expect(saved.records.single.data['batteryPercent'], 80);
    },
  );

  test('refuses to persist mock data or an anonymous device', () async {
    final mockBundle = EvidenceBundle.completed(
      deviceId: 'test-device',
      deviceName: 'AIPIN_TEST',
      verdict: ObservationVerdict.passed,
      reason: 'test',
      isMock: true,
    );
    final anonymousBundle = EvidenceBundle.completed(
      deviceId: '',
      deviceName: '',
      verdict: ObservationVerdict.passed,
      reason: 'test',
    );

    await expectLater(repository.save(mockBundle), throwsArgumentError);
    await expectLater(repository.save(anonymousBundle), throwsArgumentError);
  });
}
