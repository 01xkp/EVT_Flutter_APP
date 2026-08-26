import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'saved and interrupted records are playable only with inspected metadata',
    () {
      expect(
        LocalRecording.inProgress(
          id: 'recording-1',
          title: '录音 2026-08-21 09:28',
          relativePath: 'recording-1.m4a',
          createdAt: DateTime(2026, 8, 21, 9, 28),
        ).isPlayable,
        isFalse,
      );
      expect(
        LocalRecording.saved(
          id: 'recording-2',
          title: '客户访谈',
          relativePath: 'recording-2.m4a',
          createdAt: DateTime(2026, 8, 21, 9, 28),
          completedAt: DateTime(2026, 8, 21, 9, 29),
          duration: const Duration(seconds: 12),
          sizeBytes: 160000,
        ).isPlayable,
        isTrue,
      );
    },
  );

  test('renaming trims text and rejects an empty result', () {
    final record = LocalRecording.inProgress(
      id: 'recording-1',
      title: '初始标题',
      relativePath: 'recording-1.m4a',
      createdAt: DateTime(2026, 8, 21),
    );

    expect(record.renamed('  客户访谈  ').title, '客户访谈');
    expect(() => record.renamed('   '), throwsArgumentError);
  });
}
