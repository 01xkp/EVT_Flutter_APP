import 'package:drift/drift.dart';

@DataClassName('EvidenceRecordRow')
class SessionEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get bundleId => text()();
  IntColumn get sequence => integer()();
  TextColumn get recordKind => text()();
  TextColumn get source => text()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get payloadJson => text()();
}
