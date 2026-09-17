import 'dart:convert';

import 'package:aipin/features/device_session/domain/firmware_update_checkpoint.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesFirmwareUpdateCheckpointRepository
    implements FirmwareUpdateCheckpointRepository {
  static const _keyPrefix = 'dvt.wqota.checkpoint.';

  @override
  Future<FirmwareUpdateCheckpoint?> find(String deviceId) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('$_keyPrefix$deviceId');
    if (raw == null) {
      return null;
    }
    try {
      final json = jsonDecode(raw);
      if (json is! Map) {
        return null;
      }
      final packageHash = json['packageHash'];
      final imageCrc32 = json['imageCrc32'];
      final packageVersion = json['packageVersion'];
      final expectedBusinessVersion = json['expectedBusinessVersion'];
      final phaseName = json['phase'];
      final nextOffset = json['nextOffset'];
      final nextLength = json['nextLength'];
      final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
      final phase = switch (phaseName) {
        'transferring' => FirmwareUpdateCheckpointPhase.transferring,
        'awaitingReconnect' => FirmwareUpdateCheckpointPhase.awaitingReconnect,
        _ => null,
      };
      if (packageHash is! String ||
          imageCrc32 is! int ||
          packageVersion is! int ||
          expectedBusinessVersion is! String ||
          expectedBusinessVersion.trim().isEmpty ||
          phase == null ||
          nextOffset is! int ||
          nextLength is! int ||
          updatedAt == null ||
          imageCrc32 < 0 ||
          imageCrc32 > 0xFFFFFFFF ||
          packageVersion < 0 ||
          packageVersion > 0xFFFF ||
          nextOffset < 0 ||
          nextLength < 0) {
        return null;
      }
      return FirmwareUpdateCheckpoint(
        deviceId: deviceId,
        packageHash: packageHash,
        imageCrc32: imageCrc32,
        packageVersion: packageVersion,
        expectedBusinessVersion: expectedBusinessVersion,
        phase: phase,
        nextOffset: nextOffset,
        nextLength: nextLength,
        updatedAt: updatedAt.toUtc(),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  Future<void> save(FirmwareUpdateCheckpoint checkpoint) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '$_keyPrefix${checkpoint.deviceId}',
      jsonEncode(<String, Object>{
        'packageHash': checkpoint.packageHash,
        'imageCrc32': checkpoint.imageCrc32,
        'packageVersion': checkpoint.packageVersion,
        'expectedBusinessVersion': checkpoint.expectedBusinessVersion,
        'phase': checkpoint.phase.name,
        'nextOffset': checkpoint.nextOffset,
        'nextLength': checkpoint.nextLength,
        'updatedAt': checkpoint.updatedAt.toUtc().toIso8601String(),
      }),
    );
  }

  @override
  Future<void> clear(String deviceId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('$_keyPrefix$deviceId');
  }
}
