import 'package:evt_ble_app/features/local_recording/domain/local_recording.dart';
import 'package:evt_ble_app/features/local_recording/domain/local_recording_repository.dart';

class FakeLocalRecordingRepository implements LocalRecordingRepository {
  FakeLocalRecordingRepository([List<LocalRecording> values = const []])
    : values = [...values];

  final List<LocalRecording> values;
  bool failReads = false;

  @override
  Future<List<LocalRecording>> all() async {
    if (failReads) {
      throw StateError('read failed');
    }
    final copy = [...values]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(copy);
  }

  @override
  Future<void> delete(String id) async {
    values.removeWhere((value) => value.id == id);
  }

  @override
  Future<void> save(LocalRecording recording) async {
    values.add(recording);
  }

  @override
  Future<void> update(LocalRecording recording) async {
    final index = values.indexWhere((value) => value.id == recording.id);
    if (index == -1) {
      throw StateError('missing recording');
    }
    values[index] = recording;
  }
}
