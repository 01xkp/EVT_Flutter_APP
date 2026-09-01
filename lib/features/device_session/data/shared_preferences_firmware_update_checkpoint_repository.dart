import 'dart:convert';

import 'package:aipin/features/device_session/domain/firmware_update_checkpoint.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesFirmwareUpdateCheckpointRepository
    implements FirmwareUpdateCheckpointRepository {
  static const _keyPrefix = 'firmware.update.checkpoint.';

  @override
  Future<FirmwareUpdateCheckpoint?> find(String deviceId) async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString('$_keyPrefix$deviceId');
    if (value == null) {
      return null;
    }
    try {
      final json = jsonDecode(value) as Map<String, Object?>;
      final packageHash = json['packageHash'] as String?;
      final offset = json['offset'] as int?;
      final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
      if (packageHash == null || offset == null || updatedAt == null) {
        return null;
      }
      return FirmwareUpdateCheckpoint(
        deviceId: deviceId,
        packageHash: packageHash,
        offset: offset,
        updatedAt: updatedAt,
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
      jsonEncode({
        'packageHash': checkpoint.packageHash,
        'offset': checkpoint.offset,
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
