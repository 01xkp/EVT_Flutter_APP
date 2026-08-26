import 'package:aipin/core/protocol/device_event.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';
import 'package:aipin/features/observation/domain/observation_run.dart';
import 'package:aipin/features/observation/domain/observation_scenario.dart';
import 'package:aipin/features/observation/domain/observation_verdict.dart';

class VerificationResult {
  const VerificationResult({
    required this.verdict,
    required this.reason,
    required this.expectedEvidence,
    this.missingFields = const [],
  });

  final ObservationVerdict verdict;
  final String reason;
  final List<String> expectedEvidence;
  final List<String> missingFields;
}

class ObservationVerifier {
  VerificationResult verify(ObservationRun run) {
    final missingFields = _missingFields(run);
    if (missingFields.isNotEmpty) {
      return VerificationResult(
        verdict: ObservationVerdict.unverifiable,
        reason: '缺少可验证证据：${missingFields.join('、')}。',
        expectedEvidence: run.scenario.expectedEvidence,
        missingFields: missingFields,
      );
    }
    if (run.events.any((event) => event.kind == DeviceEventKind.unknown)) {
      return VerificationResult(
        verdict: ObservationVerdict.unverifiable,
        reason: '存在无法识别的协议事件。',
        expectedEvidence: run.scenario.expectedEvidence,
        missingFields: const ['validProtocolEvents'],
      );
    }

    final failureReason = _failureReason(run);
    if (failureReason != null) {
      return VerificationResult(
        verdict: ObservationVerdict.failed,
        reason: failureReason,
        expectedEvidence: run.scenario.expectedEvidence,
      );
    }
    return VerificationResult(
      verdict: ObservationVerdict.passed,
      reason: '已获得所需设备证据。',
      expectedEvidence: run.scenario.expectedEvidence,
    );
  }

  List<String> _missingFields(ObservationRun run) {
    final finalSnapshot = run.finalSnapshot;
    return [
      for (final field in run.scenario.requiredFields)
        if (!_isAvailable(
          field,
          run.initialSnapshot,
          finalSnapshot,
          run.manualNote,
        ))
          field.key,
    ];
  }

  bool _isAvailable(
    ObservationEvidenceField field,
    DeviceSnapshot initialSnapshot,
    DeviceSnapshot? finalSnapshot,
    String? manualNote,
  ) {
    return switch (field) {
      ObservationEvidenceField.initialState =>
        initialSnapshot.state != DeviceState.unknown,
      ObservationEvidenceField.finalState =>
        finalSnapshot != null && finalSnapshot.state != DeviceState.unknown,
      ObservationEvidenceField.batteryPercent =>
        finalSnapshot?.batteryPercent != null,
      ObservationEvidenceField.chargingState =>
        finalSnapshot?.isCharging != null,
      ObservationEvidenceField.standbyPowerMilliwatts =>
        finalSnapshot?.standbyPowerMilliwatts != null,
      ObservationEvidenceField.manualNote =>
        manualNote?.trim().isNotEmpty ?? false,
    };
  }

  String? _failureReason(ObservationRun run) {
    final finalState = run.finalSnapshot?.state;
    switch (run.scenario) {
      case ObservationScenario.vadRecording:
        if (!_containsOrderedEvents(run.events, const [
          DeviceEventKind.recordingStarted,
          DeviceEventKind.silenceEnded,
        ])) {
          return '未观察到完整的录音与静音结束事件序列。';
        }
        return finalState == DeviceState.standby ? null : 'VAD 结束后设备未回到待机状态。';
      case ObservationScenario.deviceAccess:
        return finalState == DeviceState.unbound ||
                finalState == DeviceState.safeOff
            ? '设备拒绝提供可用状态。'
            : null;
      case ObservationScenario.recovery:
        return finalState == DeviceState.safeOff ? '恢复后设备仍处于安全关机状态。' : null;
      case ObservationScenario.batteryAndCharging:
      case ObservationScenario.standbyPower:
      case ObservationScenario.physicalFeedback:
        return null;
    }
  }

  bool _containsOrderedEvents(
    List<DeviceEvent> events,
    List<DeviceEventKind> expected,
  ) {
    var expectedIndex = 0;
    for (final event in events) {
      if (event.kind == expected[expectedIndex]) {
        expectedIndex += 1;
        if (expectedIndex == expected.length) {
          return true;
        }
      }
    }
    return false;
  }
}
