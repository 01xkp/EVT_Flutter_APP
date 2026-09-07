import 'package:drift/drift.dart';

@DataClassName('DeviceFileDownloadCheckpointRow')
class DeviceFileDownloadCheckpoints extends Table {
  TextColumn get id => text()();
  TextColumn get deviceId => text()();
  TextColumn get nameSlotBase64 => text()();
  TextColumn get recordingId => text()();
  TextColumn get expectedLength => text()();
  TextColumn get expectedCrc32 => text()();
  IntColumn get receivedBytes => integer()();
  TextColumn get phase => text().withDefault(const Constant('downloading'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
