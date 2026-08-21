import 'package:drift/drift.dart';

@DataClassName('EvidenceBundleRow')
class EvidenceBundles extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get deviceId => text()();
  TextColumn get deviceName => text()();
  TextColumn get firmwareVersion => text().nullable()();
  TextColumn get verdict => text()();
  TextColumn get reason => text()();
  TextColumn get manualNote => text().nullable()();
  TextColumn get diagnosticJson => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
