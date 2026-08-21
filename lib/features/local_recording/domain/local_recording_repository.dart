import 'package:evt_ble_app/features/local_recording/domain/local_recording.dart';

abstract interface class LocalRecordingRepository {
  Future<List<LocalRecording>> all();
  Future<void> save(LocalRecording recording);
  Future<void> update(LocalRecording recording);
  Future<void> delete(String id);
}
