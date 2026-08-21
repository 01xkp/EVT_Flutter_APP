import 'dart:async';

import 'package:evt_ble_app/core/ble/ble_transport.dart';
import 'package:evt_ble_app/core/ble/reactive_ble_transport.dart';
import 'package:evt_ble_app/core/persistence/app_database.dart';
import 'package:evt_ble_app/features/evidence/data/drift_evidence_repository.dart';
import 'package:evt_ble_app/features/evidence/domain/evidence_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final bleTransportProvider = Provider<BleTransport>((ref) {
  return ReactiveBleTransport();
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(() => unawaited(database.close()));
  return database;
});

final evidenceRepositoryProvider = Provider<EvidenceRepository>((ref) {
  return DriftEvidenceRepository(ref.watch(appDatabaseProvider));
});
