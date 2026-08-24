import 'package:aipin/features/research_beta/domain/research_analytics.dart';
import 'package:aipin/features/research_beta/domain/research_capture.dart';

abstract interface class ResearchCaptureRepository {
  Future<List<ResearchCapture>> all();
  Stream<List<ResearchCapture>> watchAll();
  Future<ResearchCapture?> findById(String id);
  Future<ResearchCapture?> findByOriginalLocalRecordingId(
    String originalLocalRecordingId,
  );
  Future<List<ResearchCapture>> findNonterminal();
  Future<void> save(ResearchCapture capture);
  Future<void> update(ResearchCapture capture);
  Future<void> delete(String id);
  Future<void> deleteAllCaptures();
  Future<void> saveEvent(ResearchEvent event);
  Future<List<ResearchEvent>> eventsForCapture(String captureId);
  Future<void> deleteAllEvents();
  Future<void> saveAggregate(ResearchAggregate aggregate);
  Future<ResearchAggregate?> loadAggregate(String participantId);
  Future<void> deleteExpiredAggregates(DateTime oldestAllowedCreatedAt);
}
