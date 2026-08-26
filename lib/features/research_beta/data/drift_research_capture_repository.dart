import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:aipin/core/persistence/app_database.dart';
import 'package:aipin/features/research_beta/domain/research_analytics.dart';
import 'package:aipin/features/research_beta/domain/research_capture.dart';
import 'package:aipin/features/research_beta/domain/research_capture_repository.dart';

class DriftResearchCaptureRepository implements ResearchCaptureRepository {
  DriftResearchCaptureRepository(this._database);

  final AppDatabase _database;

  @override
  Future<List<ResearchCapture>> all() async {
    final rows = await (_database.select(
      _database.researchCaptures,
    )..orderBy([(row) => OrderingTerm.desc(row.createdAt)])).get();
    return rows.map(_captureFromRow).toList(growable: false);
  }

  @override
  Future<void> delete(String id) async {
    await (_database.delete(
      _database.researchCaptures,
    )..where((row) => row.id.equals(id))).go();
  }

  @override
  Future<void> deleteAllCaptures() =>
      _database.delete(_database.researchCaptures).go().then((_) {});

  @override
  Future<void> deleteAllEvents() =>
      _database.delete(_database.researchEvents).go().then((_) {});

  @override
  Future<void> deleteExpiredAggregates(DateTime oldestAllowedCreatedAt) async {
    await (_database.delete(_database.researchAggregates)..where(
          (row) => row.createdAt.isSmallerThanValue(oldestAllowedCreatedAt),
        ))
        .go();
  }

  @override
  Future<ResearchCapture?> findById(String id) async {
    final row = await (_database.select(
      _database.researchCaptures,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    return row == null ? null : _captureFromRow(row);
  }

  @override
  Future<ResearchCapture?> findByOriginalLocalRecordingId(
    String originalLocalRecordingId,
  ) async {
    final row =
        await (_database.select(_database.researchCaptures)..where(
              (row) =>
                  row.originalLocalRecordingId.equals(originalLocalRecordingId),
            ))
            .getSingleOrNull();
    return row == null ? null : _captureFromRow(row);
  }

  @override
  Future<List<ResearchCapture>> findNonterminal() async {
    final rows =
        await (_database.select(_database.researchCaptures)
              ..where(
                (row) => row.processingState.isNotIn(<String>[
                  ResearchProcessingState.completed.name,
                  ResearchProcessingState.uploadFailed.name,
                  ResearchProcessingState.transcriptionFailed.name,
                  ResearchProcessingState.summaryFailed.name,
                ]),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
            .get();
    return rows.map(_captureFromRow).toList(growable: false);
  }

  @override
  Future<List<ResearchEvent>> eventsForCapture(String captureId) async {
    final rows =
        await (_database.select(_database.researchEvents)
              ..where((row) => row.captureId.equals(captureId))
              ..orderBy([(row) => OrderingTerm.asc(row.occurredAt)]))
            .get();
    return rows.map(_eventFromRow).toList(growable: false);
  }

  @override
  Future<ResearchAggregate?> loadAggregate(String participantId) async {
    final row =
        await (_database.select(_database.researchAggregates)
              ..where((row) => row.participantId.equals(participantId)))
            .getSingleOrNull();
    return row == null ? null : _aggregateFromRow(row);
  }

  @override
  Future<void> save(ResearchCapture capture) async {
    final originalLocalRecordingId = capture.originalLocalRecordingId;
    if (originalLocalRecordingId != null &&
        await findByOriginalLocalRecordingId(originalLocalRecordingId) !=
            null) {
      throw StateError('该本机录音已经创建过 AI 整理。');
    }
    await _database
        .into(_database.researchCaptures)
        .insert(_captureCompanion(capture));
  }

  @override
  Future<void> saveAggregate(ResearchAggregate aggregate) async {
    await _database
        .into(_database.researchAggregates)
        .insertOnConflictUpdate(_aggregateCompanion(aggregate));
  }

  @override
  Future<void> saveEvent(ResearchEvent event) async {
    await _database
        .into(_database.researchEvents)
        .insert(_eventCompanion(event));
  }

  @override
  Future<void> update(ResearchCapture capture) async {
    await _database
        .update(_database.researchCaptures)
        .replace(_captureRow(capture));
  }

  @override
  Stream<List<ResearchCapture>> watchAll() {
    return (_database.select(_database.researchCaptures)
          ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
        .watch()
        .map((rows) => rows.map(_captureFromRow).toList(growable: false));
  }

  ResearchCapture _captureFromRow(ResearchCaptureRow row) {
    final decodedTags = jsonDecode(row.tagsJson);
    return ResearchCapture(
      id: row.id,
      participantId: row.participantId,
      origin: ResearchCaptureOrigin.values.byName(row.origin),
      sourceType: row.sourceType,
      relativePath: row.relativePath,
      duration: Duration(milliseconds: row.durationMs),
      createdAt: row.createdAt,
      processingState: ResearchProcessingState.values.byName(
        row.processingState,
      ),
      inboxState: ResearchInboxState.values.byName(row.inboxState),
      originalLocalRecordingId: row.originalLocalRecordingId,
      jobId: row.jobId,
      asrSegments: _segmentsFromJson(row.asrSegmentsJson),
      noteId: row.noteId,
      generationTaskId: row.generationTaskId,
      rawTranscript: row.rawTranscript,
      correctedTranscript: row.correctedTranscript,
      title: row.title,
      summary: row.summary,
      tags: decodedTags is List
          ? List.unmodifiable(decodedTags.whereType<String>())
          : const [],
      actionContext: row.actionContext,
      failureReason: row.failureReason,
      openedAt: row.openedAt,
      handledAt: row.handledAt,
      completedAt: row.completedAt,
    );
  }

  ResearchCaptureRow _captureRow(ResearchCapture value) {
    return ResearchCaptureRow(
      id: value.id,
      participantId: value.participantId,
      origin: value.origin.name,
      sourceType: value.sourceType,
      originalLocalRecordingId: value.originalLocalRecordingId,
      relativePath: value.relativePath,
      durationMs: value.duration.inMilliseconds,
      createdAt: value.createdAt,
      completedAt: value.completedAt,
      processingState: value.processingState.name,
      inboxState: value.inboxState.name,
      jobId: value.jobId,
      asrSegmentsJson: jsonEncode(
        value.asrSegments
            .map(
              (segment) => <String, Object?>{
                'index': segment.index,
                'relative_path': segment.relativePath,
                'job_id': segment.jobId,
              },
            )
            .toList(growable: false),
      ),
      noteId: value.noteId,
      generationTaskId: value.generationTaskId,
      rawTranscript: value.rawTranscript,
      correctedTranscript: value.correctedTranscript,
      title: value.title,
      summary: value.summary,
      tagsJson: jsonEncode(value.tags),
      actionContext: value.actionContext,
      failureReason: value.failureReason,
      openedAt: value.openedAt,
      handledAt: value.handledAt,
    );
  }

  ResearchCapturesCompanion _captureCompanion(ResearchCapture value) {
    return ResearchCapturesCompanion.insert(
      id: value.id,
      participantId: value.participantId,
      origin: value.origin.name,
      sourceType: value.sourceType,
      originalLocalRecordingId: Value(value.originalLocalRecordingId),
      relativePath: value.relativePath,
      durationMs: value.duration.inMilliseconds,
      createdAt: value.createdAt,
      completedAt: Value(value.completedAt),
      processingState: value.processingState.name,
      inboxState: value.inboxState.name,
      jobId: Value(value.jobId),
      asrSegmentsJson: Value(
        jsonEncode(
          value.asrSegments
              .map(
                (segment) => <String, Object?>{
                  'index': segment.index,
                  'relative_path': segment.relativePath,
                  'job_id': segment.jobId,
                },
              )
              .toList(growable: false),
        ),
      ),
      noteId: Value(value.noteId),
      generationTaskId: Value(value.generationTaskId),
      rawTranscript: Value(value.rawTranscript),
      correctedTranscript: Value(value.correctedTranscript),
      title: Value(value.title),
      summary: Value(value.summary),
      tagsJson: Value(jsonEncode(value.tags)),
      actionContext: Value(value.actionContext),
      failureReason: Value(value.failureReason),
      openedAt: Value(value.openedAt),
      handledAt: Value(value.handledAt),
    );
  }

  ResearchEvent _eventFromRow(ResearchEventRow row) {
    return ResearchEvent(
      id: row.id,
      participantId: row.participantId,
      captureId: row.captureId,
      type: ResearchEventType.values.byName(row.type),
      occurredAt: row.occurredAt,
      processingState: row.processingState == null
          ? null
          : ResearchProcessingState.values.byName(row.processingState!),
      durationBucket: row.durationBucket,
      action: row.action == null
          ? null
          : ResearchCardAction.values.byName(row.action!),
      qualityFeedback: row.qualityFeedback,
      dailyUnderstanding: row.dailyUnderstanding,
      elapsedMilliseconds: row.elapsedMilliseconds,
    );
  }

  List<ResearchAsrSegment> _segmentsFromJson(String encoded) {
    try {
      final value = jsonDecode(encoded);
      if (value is! List) {
        return const <ResearchAsrSegment>[];
      }
      final segments = <ResearchAsrSegment>[];
      for (final item in value) {
        if (item is! Map) {
          return const <ResearchAsrSegment>[];
        }
        final index = item['index'];
        final relativePath = item['relative_path'];
        final jobId = item['job_id'];
        if (index is! int ||
            relativePath is! String ||
            (jobId != null && jobId is! String)) {
          return const <ResearchAsrSegment>[];
        }
        segments.add(
          ResearchAsrSegment(
            index: index,
            relativePath: relativePath,
            jobId: jobId as String?,
          ),
        );
      }
      return ResearchCapture.fromDirectAiVoice(
        id: 'validation',
        participantId: 'validation',
        relativePath: 'validation.m4a',
        duration: const Duration(seconds: 2),
        createdAt: DateTime(2000),
      ).withAsrSegments(segments).asrSegments;
    } on FormatException {
      return const <ResearchAsrSegment>[];
    } on ArgumentError {
      return const <ResearchAsrSegment>[];
    }
  }

  ResearchEventsCompanion _eventCompanion(ResearchEvent value) {
    return ResearchEventsCompanion.insert(
      id: value.id,
      participantId: value.participantId,
      captureId: value.captureId,
      type: value.type.name,
      occurredAt: value.occurredAt,
      processingState: Value(value.processingState?.name),
      durationBucket: Value(value.durationBucket),
      action: Value(value.action?.name),
      qualityFeedback: Value(value.qualityFeedback),
      dailyUnderstanding: Value(value.dailyUnderstanding),
      elapsedMilliseconds: Value(value.elapsedMilliseconds),
    );
  }

  ResearchAggregate _aggregateFromRow(ResearchAggregateRow row) {
    return ResearchAggregate(
      participantId: row.participantId,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      captureCount: row.captureCount,
      handledCount: row.handledCount,
      usefulReuseCount: row.usefulReuseCount,
      accurateFeedbackCount: row.accurateFeedbackCount,
      inaccurateFeedbackCount: row.inaccurateFeedbackCount,
      understoodCount: row.understoodCount,
      notUnderstoodCount: row.notUnderstoodCount,
    );
  }

  ResearchAggregatesCompanion _aggregateCompanion(ResearchAggregate value) {
    return ResearchAggregatesCompanion.insert(
      participantId: value.participantId,
      createdAt: value.createdAt,
      updatedAt: value.updatedAt,
      captureCount: Value(value.captureCount),
      handledCount: Value(value.handledCount),
      usefulReuseCount: Value(value.usefulReuseCount),
      accurateFeedbackCount: Value(value.accurateFeedbackCount),
      inaccurateFeedbackCount: Value(value.inaccurateFeedbackCount),
      understoodCount: Value(value.understoodCount),
      notUnderstoodCount: Value(value.notUnderstoodCount),
    );
  }
}
