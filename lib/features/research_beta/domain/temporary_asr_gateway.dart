sealed class AsrOutcome<T> {
  const AsrOutcome();
}

class AsrSuccess<T> extends AsrOutcome<T> {
  const AsrSuccess(this.value);

  final T value;
}

enum AsrFailureKind {
  unavailable,
  network,
  upload,
  transcription,
  summaryUnsupported,
  remote,
  invalidResponse,
}

class AsrFailure<T> extends AsrOutcome<T> {
  const AsrFailure({required this.kind, required this.message});

  final AsrFailureKind kind;
  final String message;
}

enum AsrJobStatus { pending, completed, failed }

class AsrJob {
  const AsrJob({required this.id, required this.status, this.message});

  final String id;
  final AsrJobStatus status;
  final String? message;
}

class AsrTranscript {
  const AsrTranscript({
    required this.text,
    required this.relativePath,
    required this.variant,
    required this.engine,
  });

  final String text;
  final String relativePath;
  final String variant;
  final String engine;
}

class AsrNoteTask {
  const AsrNoteTask({required this.noteId, required this.generationTaskId});

  final String noteId;
  final String generationTaskId;
}

enum AsrGenerationStatus { pending, completed, failed }

class AsrGeneratedNote {
  const AsrGeneratedNote({
    required this.title,
    required this.summary,
    required this.tags,
    this.actionContext,
  });

  final String title;
  final String summary;
  final List<String> tags;
  final String? actionContext;
}

abstract interface class TemporaryAsrGateway {
  Future<AsrOutcome<AsrJob>> submitAudio(String absoluteAudioPath);
  Future<AsrOutcome<AsrJob>> pollJob(String jobId);
  Future<AsrOutcome<AsrTranscript>> fetchTranscript(String jobId);
  Future<AsrOutcome<AsrNoteTask>> createNote({
    required String jobId,
    required AsrTranscript transcript,
  });
  Future<AsrOutcome<AsrGenerationStatus>> pollGenerationTask({
    required String noteId,
    required String generationTaskId,
  });
  Future<AsrOutcome<AsrGeneratedNote>> fetchCompletedNote(String noteId);
  Future<AsrOutcome<void>> deleteNote(String noteId);
}
