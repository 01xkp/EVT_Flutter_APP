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
  // Retained solely to read and normalize pre-EVT/DVT database rows. EVT
  // checkpoint behavior does not expose or branch on a phase value.
  TextColumn get phase => text().withDefault(const Constant('downloading'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
