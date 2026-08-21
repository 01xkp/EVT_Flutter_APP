import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:evt_ble_app/core/persistence/tables/evidence_bundles.dart';
import 'package:evt_ble_app/core/persistence/tables/local_recordings.dart';
import 'package:evt_ble_app/core/persistence/tables/session_events.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [EvidenceBundles, SessionEvents, LocalRecordings])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'evt_evidence'));

  AppDatabase.forTesting({QueryExecutor? executor})
    : super(executor ?? NativeDatabase.memory());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(localRecordings);
      }
    },
  );
}
