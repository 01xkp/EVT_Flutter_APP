import 'package:aipin/core/protocol/device_event.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';

DeviceSnapshot snapshot({
  DeviceState state = DeviceState.standby,
  DateTime? observedAt,
  String source = 'test',
}) {
  return DeviceSnapshot(
    state: state,
    observedAt: observedAt ?? DateTime(2026, 8, 21),
    source: source,
  );
}

DeviceEvent event(DeviceEventKind kind) {
  return DeviceEvent(
    kind: kind,
    occurredAt: DateTime(2026, 8, 21),
    source: 'test',
  );
}
