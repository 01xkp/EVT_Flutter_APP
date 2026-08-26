import 'package:drift/drift.dart';

@DataClassName('ResearchEventRow')
class ResearchEvents extends Table {
  TextColumn get id => text()();
  TextColumn get participantId => text()();
  TextColumn get captureId => text()();
  TextColumn get type => text()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get processingState => text().nullable()();
  TextColumn get durationBucket => text().nullable()();
  TextColumn get action => text().nullable()();
  BoolColumn get qualityFeedback => boolean().nullable()();
  BoolColumn get dailyUnderstanding => boolean().nullable()();
  IntColumn get elapsedMilliseconds => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ResearchAggregateRow')
class ResearchAggregates extends Table {
  TextColumn get participantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get captureCount => integer().withDefault(const Constant(0))();
  IntColumn get handledCount => integer().withDefault(const Constant(0))();
  IntColumn get usefulReuseCount => integer().withDefault(const Constant(0))();
  IntColumn get accurateFeedbackCount =>
      integer().withDefault(const Constant(0))();
  IntColumn get inaccurateFeedbackCount =>
      integer().withDefault(const Constant(0))();
  IntColumn get understoodCount => integer().withDefault(const Constant(0))();
  IntColumn get notUnderstoodCount =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {participantId};
}
