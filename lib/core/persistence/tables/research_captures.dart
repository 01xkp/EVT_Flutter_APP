import 'package:drift/drift.dart';

@DataClassName('ResearchCaptureRow')
class ResearchCaptures extends Table {
  TextColumn get id => text()();
  TextColumn get participantId => text()();
  TextColumn get origin => text()();
  TextColumn get sourceType => text()();
  TextColumn get originalLocalRecordingId => text().nullable().unique()();
  TextColumn get relativePath => text()();
  IntColumn get durationMs => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get processingState => text()();
  TextColumn get inboxState => text()();
  TextColumn get jobId => text().nullable()();
  TextColumn get asrSegmentsJson => text().withDefault(const Constant('[]'))();
  TextColumn get noteId => text().nullable()();
  TextColumn get generationTaskId => text().nullable()();
  TextColumn get rawTranscript => text().nullable()();
  TextColumn get correctedTranscript => text().nullable()();
  TextColumn get title => text().nullable()();
  TextColumn get summary => text().nullable()();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  TextColumn get actionContext => text().nullable()();
  TextColumn get failureReason => text().nullable()();
  DateTimeColumn get openedAt => dateTime().nullable()();
  DateTimeColumn get handledAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
