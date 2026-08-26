import 'dart:async';

import 'package:aipin/features/research_beta/domain/research_analytics.dart';
import 'package:aipin/features/research_beta/domain/audio_segmenter.dart';
import 'package:aipin/features/research_beta/domain/research_capture.dart';
import 'package:aipin/features/research_beta/domain/research_capture_file_store.dart';
import 'package:aipin/features/research_beta/domain/research_capture_repository.dart';
import 'package:aipin/features/research_beta/domain/research_trial.dart';
import 'package:aipin/features/research_beta/domain/temporary_asr_gateway.dart';

class FakeResearchCaptureRepository implements ResearchCaptureRepository {
  final Map<String, ResearchCapture> captures = <String, ResearchCapture>{};
  final List<ResearchEvent> events = <ResearchEvent>[];
  final Map<String, ResearchAggregate> aggregates =
      <String, ResearchAggregate>{};
  final _changes = StreamController<List<ResearchCapture>>.broadcast();

  @override
  Future<List<ResearchCapture>> all() async {
    final values = captures.values.toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return values;
  }

  @override
  Future<void> delete(String id) async {
    captures.remove(id);
    _emit();
  }

  @override
  Future<void> deleteAllCaptures() async {
    captures.clear();
    _emit();
  }

  @override
  Future<void> deleteAllEvents() async => events.clear();

  @override
  Future<void> deleteExpiredAggregates(DateTime oldestAllowedCreatedAt) async {
    aggregates.removeWhere(
      (_, aggregate) => aggregate.createdAt.isBefore(oldestAllowedCreatedAt),
    );
  }

  @override
  Future<List<ResearchEvent>> eventsForCapture(String captureId) async {
    return events.where((event) => event.captureId == captureId).toList();
  }

  @override
  Future<ResearchCapture?> findById(String id) async => captures[id];

  @override
  Future<ResearchCapture?> findByOriginalLocalRecordingId(
    String originalLocalRecordingId,
  ) async {
    for (final capture in captures.values) {
      if (capture.originalLocalRecordingId == originalLocalRecordingId) {
        return capture;
      }
    }
    return null;
  }

  @override
  Future<List<ResearchCapture>> findNonterminal() async {
    return captures.values.where((capture) => !capture.isTerminal).toList();
  }

  @override
  Future<ResearchAggregate?> loadAggregate(String participantId) async =>
      aggregates[participantId];

  @override
  Future<void> save(ResearchCapture capture) async {
    if (capture.originalLocalRecordingId != null &&
        await findByOriginalLocalRecordingId(
              capture.originalLocalRecordingId!,
            ) !=
            null) {
      throw StateError('duplicate local upload');
    }
    captures[capture.id] = capture;
    _emit();
  }

  @override
  Future<void> saveAggregate(ResearchAggregate aggregate) async {
    aggregates[aggregate.participantId] = aggregate;
  }

  @override
  Future<void> saveEvent(ResearchEvent event) async => events.add(event);

  @override
  Future<void> update(ResearchCapture capture) async {
    captures[capture.id] = capture;
    _emit();
  }

  @override
  Stream<List<ResearchCapture>> watchAll() async* {
    yield await all();
    yield* _changes.stream;
  }

  void _emit() async {
    _changes.add(await all());
  }
}

class FakeResearchCaptureFileStore implements ResearchCaptureFileStore {
  final List<String> copiedSources = <String>[];
  final List<String> deletedPaths = <String>[];
  final List<String> discardedIds = <String>[];
  int sizeBytes = 24;

  @override
  Future<String> absolutePathFor(String relativePath) async =>
      '/research/$relativePath';

  @override
  Future<CompletedResearchCaptureFile> copyFromLocal({
    required String id,
    required String sourcePath,
  }) async {
    copiedSources.add(sourcePath);
    return CompletedResearchCaptureFile(
      relativePath: '$id.m4a',
      absolutePath: '/research/$id.m4a',
      sizeBytes: sizeBytes,
    );
  }

  @override
  Future<PendingResearchCaptureFile> createPending({required String id}) async {
    return PendingResearchCaptureFile(
      id: id,
      temporaryPath: '/research/$id.part.m4a',
      relativePath: '$id.m4a',
    );
  }

  @override
  Future<void> delete(String relativePath) async =>
      deletedPaths.add(relativePath);

  @override
  Future<void> deleteAll() async => deletedPaths.add('*');

  @override
  Future<void> discard(PendingResearchCaptureFile pending) async {
    discardedIds.add(pending.id);
  }

  @override
  Future<CompletedResearchCaptureFile> finalize(
    PendingResearchCaptureFile pending,
  ) async {
    return CompletedResearchCaptureFile(
      relativePath: pending.relativePath,
      absolutePath: '/research/${pending.relativePath}',
      sizeBytes: sizeBytes,
    );
  }

  @override
  Future<String> absoluteSegmentPathFor({
    required String captureId,
    required int index,
  }) async =>
      '/research/$captureId.segment-${index.toString().padLeft(4, '0')}.m4a';

  @override
  Future<String> relativeSegmentPathFor({
    required String captureId,
    required int index,
  }) async => '$captureId.segment-${index.toString().padLeft(4, '0')}.m4a';

  @override
  Future<String> segmentOutputPathPrefixFor({
    required String captureId,
  }) async => '/research/$captureId.segment-';
}

class FakeAudioSegmenter implements AudioSegmenter {
  final List<AudioSegmentationRequest> requests = <AudioSegmentationRequest>[];
  List<AudioSegment> segments = const <AudioSegment>[
    AudioSegment(index: 0, duration: Duration(seconds: 12)),
  ];
  Object? error;

  @override
  Future<List<AudioSegment>> splitM4a(AudioSegmentationRequest request) async {
    requests.add(request);
    if (error case final Exception exception) {
      throw exception;
    }
    return segments;
  }
}

class FakeResearchTrialStore implements ResearchTrialStore {
  FakeResearchTrialStore([this.value]);

  ResearchTrial? value;

  @override
  Future<ResearchTrial?> load() async => value;

  @override
  Future<void> save(ResearchTrial trial) async => value = trial;
}

class FakeTemporaryAsrGateway implements TemporaryAsrGateway {
  int submitCount = 0;
  int noteRequestCount = 0;
  final List<String> pollJobIds = <String>[];
  final List<String> deletedNoteIds = <String>[];
  final List<String> createdNoteJobIds = <String>[];
  final List<String> createdNoteTranscripts = <String>[];
  final List<String> submittedAudioPaths = <String>[];
  final Map<String, AsrOutcome<AsrTranscript>> transcriptOutcomesByJobId =
      <String, AsrOutcome<AsrTranscript>>{};
  final List<AsrOutcome<AsrJob>> submitOutcomes = <AsrOutcome<AsrJob>>[];
  AsrOutcome<AsrJob> submitOutcome = const AsrSuccess<AsrJob>(
    AsrJob(id: 'job-1', status: AsrJobStatus.pending),
  );
  AsrOutcome<AsrJob> pollJobOutcome = const AsrSuccess<AsrJob>(
    AsrJob(id: 'job-1', status: AsrJobStatus.completed),
  );
  AsrOutcome<AsrTranscript> transcriptOutcome = const AsrSuccess<AsrTranscript>(
    AsrTranscript(
      text: '机器转写',
      relativePath: 'capture.m4a',
      variant: 'original',
      engine: 'sensevoice',
    ),
  );
  AsrOutcome<AsrNoteTask> noteOutcome = const AsrSuccess<AsrNoteTask>(
    AsrNoteTask(noteId: 'note-1', generationTaskId: 'task-1'),
  );
  AsrOutcome<AsrGenerationStatus> generationOutcome =
      const AsrSuccess<AsrGenerationStatus>(AsrGenerationStatus.completed);
  AsrOutcome<AsrGeneratedNote> generatedNoteOutcome =
      const AsrSuccess<AsrGeneratedNote>(
        AsrGeneratedNote(title: '标题', summary: '摘要', tags: <String>['标签']),
      );
  AsrOutcome<void> deleteOutcome = const AsrSuccess<void>(null);
  Object? deleteError;

  @override
  Future<AsrOutcome<AsrNoteTask>> createNote({
    required String jobId,
    required AsrTranscript transcript,
  }) async {
    noteRequestCount += 1;
    createdNoteJobIds.add(jobId);
    createdNoteTranscripts.add(transcript.text);
    return noteOutcome;
  }

  @override
  Future<AsrOutcome<void>> deleteNote(String noteId) async {
    deletedNoteIds.add(noteId);
    if (deleteError case final error?) {
      throw error;
    }
    return deleteOutcome;
  }

  @override
  Future<AsrOutcome<AsrGeneratedNote>> fetchCompletedNote(
    String noteId,
  ) async => generatedNoteOutcome;

  @override
  Future<AsrOutcome<AsrTranscript>> fetchTranscript(String jobId) async =>
      transcriptOutcomesByJobId[jobId] ?? transcriptOutcome;

  @override
  Future<AsrOutcome<AsrJob>> pollJob(String jobId) async {
    pollJobIds.add(jobId);
    return pollJobOutcome;
  }

  @override
  Future<AsrOutcome<AsrGenerationStatus>> pollGenerationTask({
    required String noteId,
    required String generationTaskId,
  }) async => generationOutcome;

  @override
  Future<AsrOutcome<AsrJob>> submitAudio(String absoluteAudioPath) async {
    submitCount += 1;
    submittedAudioPaths.add(absoluteAudioPath);
    if (submitOutcomes.isNotEmpty) {
      return submitOutcomes.removeAt(0);
    }
    return submitOutcome;
  }
}
