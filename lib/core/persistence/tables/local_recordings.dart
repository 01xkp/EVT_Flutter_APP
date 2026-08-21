import 'package:drift/drift.dart';

@DataClassName('LocalRecordingRow')
class LocalRecordings extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get relativePath => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn get durationMs => integer().nullable()();
  IntColumn get sizeBytes => integer().nullable()();
  TextColumn get state => text()();
  TextColumn get failureReason => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
