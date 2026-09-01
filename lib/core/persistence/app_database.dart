import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:aipin/core/persistence/tables/evidence_bundles.dart';
import 'package:aipin/core/persistence/tables/device_file_download_checkpoints.dart';
import 'package:aipin/core/persistence/tables/local_recordings.dart';
import 'package:aipin/core/persistence/tables/research_captures.dart';
import 'package:aipin/core/persistence/tables/research_events.dart';
import 'package:aipin/core/persistence/tables/session_events.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    EvidenceBundles,
    SessionEvents,
    LocalRecordings,
    ResearchCaptures,
    ResearchEvents,
    ResearchAggregates,
    DeviceFileDownloadCheckpoints,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'evt_evidence'));

  AppDatabase.forTesting({QueryExecutor? executor})
    : super(executor ?? NativeDatabase.memory());

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(localRecordings);
      }
      if (from < 3) {
        await migrator.createTable(researchCaptures);
        await migrator.createTable(researchEvents);
        await migrator.createTable(researchAggregates);
      } else {
        if (from < 4) {
          await migrator.addColumn(
            researchCaptures,
            researchCaptures.asrSegmentsJson,
          );
        }
        if (from < 5) {
          await migrator.addColumn(
            researchCaptures,
            researchCaptures.transcriptTitle,
          );
          await migrator.addColumn(
            researchCaptures,
            researchCaptures.summaryTitle,
          );
        }
      }
      if (from < 6) {
        await migrator.createTable(deviceFileDownloadCheckpoints);
      }
    },
  );
}
