import 'package:aipin/features/device_discovery/domain/device_candidate.dart';

class AdvertisementFilter {
  const AdvertisementFilter({
    this.namePrefix = 'AIPIN',
    this.manufacturerPrefix = const [0xA3, 0x89],
    this.serviceUuid = '0000AF30-0000-1000-8000-00805F9B34FB',
  });

  final String namePrefix;
  final List<int> manufacturerPrefix;
  final String serviceUuid;

  bool matches(DeviceCandidate candidate) => evaluate(candidate).matches;

  AdvertisementEvaluation evaluate(DeviceCandidate candidate) {
    final reasons = <String>[];
    final normalizedName = candidate.name.trim().toUpperCase();
    final normalizedPrefix = namePrefix.trim().toUpperCase();
    final expectedName = RegExp(
      '^${RegExp.escape(normalizedPrefix)}_[0-9A-F]{4}\$',
    );
    if (!expectedName.hasMatch(normalizedName)) {
      reasons.add('name_prefix');
      reasons.add('name_format');
    }
    final hasManufacturerData = _hasExactManufacturerData(
      candidate.manufacturerData,
      manufacturerPrefix,
    );
    if (!hasManufacturerData) {
      reasons.add('manufacturer_prefix');
      reasons.add('manufacturer_format');
    } else if (!_nameMatchesAddress(
      normalizedName,
      candidate.manufacturerData,
    )) {
      reasons.add('name_address_mismatch');
    }
    if (!candidate.serviceUuids.any(_matchesServiceUuid)) {
      reasons.add('service_uuid');
    }
    return AdvertisementEvaluation(
      matches: reasons.isEmpty,
      reasons: List.unmodifiable(reasons),
    );
  }

  bool _matchesServiceUuid(String value) {
    final normalized = value.trim().toUpperCase();
    final expected = serviceUuid.trim().toUpperCase();
    if (normalized == expected) {
      return true;
    }
    final expectedShort = expected.substring(4, 8);
    return normalized == expectedShort || normalized == '0X$expectedShort';
  }

  static bool _hasExactManufacturerData(List<int> actual, List<int> expected) {
    // The firmware advertises A3 89 followed by exactly six BtAddressRaw bytes.
    if (expected.length != 2 || actual.length != expected.length + 6) {
      return false;
    }
    for (var index = 0; index < expected.length; index += 1) {
      if (actual[index] != expected[index]) {
        return false;
      }
    }
    return true;
  }

  static bool _nameMatchesAddress(String name, List<int> manufacturerData) {
    final addressSuffix = manufacturerData
        .sublist(manufacturerData.length - 2)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();
    return name.endsWith('_$addressSuffix');
  }
}

class AdvertisementEvaluation {
  const AdvertisementEvaluation({required this.matches, required this.reasons});

  final bool matches;
  final List<String> reasons;
}
