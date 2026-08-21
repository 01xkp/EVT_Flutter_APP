enum ObservationScenario {
  deviceAccess,
  vadRecording,
  batteryAndCharging,
  standbyPower,
  recovery,
  physicalFeedback;

  String get title => switch (this) {
    ObservationScenario.deviceAccess => '设备访问',
    ObservationScenario.vadRecording => 'VAD 录音',
    ObservationScenario.batteryAndCharging => '电池与充电',
    ObservationScenario.standbyPower => '待机功耗',
    ObservationScenario.recovery => '恢复验证',
    ObservationScenario.physicalFeedback => '物理反馈',
  };

  List<ObservationEvidenceField> get requiredFields => switch (this) {
    ObservationScenario.deviceAccess => const [
      ObservationEvidenceField.finalState,
    ],
    ObservationScenario.vadRecording => const [
      ObservationEvidenceField.initialState,
      ObservationEvidenceField.finalState,
    ],
    ObservationScenario.batteryAndCharging => const [
      ObservationEvidenceField.batteryPercent,
      ObservationEvidenceField.chargingState,
    ],
    ObservationScenario.standbyPower => const [
      ObservationEvidenceField.standbyPowerMilliwatts,
    ],
    ObservationScenario.recovery => const [
      ObservationEvidenceField.initialState,
      ObservationEvidenceField.finalState,
    ],
    ObservationScenario.physicalFeedback => const [
      ObservationEvidenceField.manualNote,
    ],
  };

  List<String> get expectedEvidence => switch (this) {
    ObservationScenario.deviceAccess => const ['可读取的设备状态'],
    ObservationScenario.vadRecording => const ['录音开始事件', '静音结束事件', '最终待机状态'],
    ObservationScenario.batteryAndCharging => const ['电量百分比', '充电状态'],
    ObservationScenario.standbyPower => const ['待机功耗'],
    ObservationScenario.recovery => const ['恢复前状态', '恢复后状态'],
    ObservationScenario.physicalFeedback => const ['人工观察备注'],
  };
}

enum ObservationEvidenceField {
  initialState,
  finalState,
  batteryPercent,
  chargingState,
  standbyPowerMilliwatts,
  manualNote;

  String get key => name;
}
