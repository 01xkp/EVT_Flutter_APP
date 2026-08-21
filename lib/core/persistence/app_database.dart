import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:evt_ble_app/core/persistence/tables/evidence_bundles.dart';
import 'package:evt_ble_app/core/persistence/tables/session_events.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [EvidenceBundles, SessionEvents])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'evt_evidence'));

  AppDatabase.forTesting() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}
