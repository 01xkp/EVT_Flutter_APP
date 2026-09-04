import 'package:aipin/features/device_session/domain/remembered_device.dart';

enum DeviceReconnectPhase {
  idle,
  scanning,
  connecting,
  waitingToRetry,
  connected,
  exhausted,
  suppressed,
}

/// Immutable state for the private remembered-device reconnection flow.
///
/// The remembered record is intentionally available only to application code.
/// Presentation and diagnostics must not expose its transport identifiers.
class DeviceReconnectState {
  const DeviceReconnectState({
    this.phase = DeviceReconnectPhase.idle,
    this.attempt = 0,
    this.rememberedDevice,
    this.canRetry = false,
    this.failureCategory,
  }) : assert(attempt >= 0 && attempt <= 3);

  final DeviceReconnectPhase phase;
  final int attempt;
  final RememberedDevice? rememberedDevice;
  final bool canRetry;

  /// Stable, non-sensitive category suitable for a retry UI or diagnostics.
  final String? failureCategory;

  DeviceReconnectState copyWith({
    DeviceReconnectPhase? phase,
    int? attempt,
    RememberedDevice? rememberedDevice,
    bool clearRememberedDevice = false,
    bool? canRetry,
    String? failureCategory,
    bool clearFailureCategory = false,
  }) {
    return DeviceReconnectState(
      phase: phase ?? this.phase,
      attempt: attempt ?? this.attempt,
      rememberedDevice: clearRememberedDevice
          ? null
          : rememberedDevice ?? this.rememberedDevice,
      canRetry: canRetry ?? this.canRetry,
      failureCategory: clearFailureCategory
          ? null
          : failureCategory ?? this.failureCategory,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DeviceReconnectState &&
        other.phase == phase &&
        other.attempt == attempt &&
        other.rememberedDevice == rememberedDevice &&
        other.canRetry == canRetry &&
        other.failureCategory == failureCategory;
  }

  @override
  int get hashCode =>
      Object.hash(phase, attempt, rememberedDevice, canRetry, failureCategory);
}
