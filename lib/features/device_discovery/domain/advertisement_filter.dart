import 'package:evt_ble_app/features/device_discovery/domain/device_candidate.dart';

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
    final nameMatches = candidate.name.toUpperCase().startsWith(
      namePrefix.toUpperCase(),
    );
    if (nameMatches) {
      reasons.add('名称 $namePrefix');
    }

    final manufacturerMatches = _startsWith(
      candidate.manufacturerData,
      manufacturerPrefix,
    );
    if (manufacturerMatches) {
      reasons.add('厂商数据 A3 89');
    }

    final serviceMatches = candidate.serviceUuids.any(
      (uuid) => uuid.toUpperCase() == serviceUuid.toUpperCase(),
    );
    if (serviceMatches) {
      reasons.add('服务 AF30');
    }

    return AdvertisementEvaluation(
      matches: nameMatches && manufacturerMatches && serviceMatches,
      reasons: List.unmodifiable(reasons),
    );
  }

  static bool _startsWith(List<int> value, List<int> prefix) {
    if (value.length < prefix.length) {
      return false;
    }
    for (var index = 0; index < prefix.length; index += 1) {
      if (value[index] != prefix[index]) {
        return false;
      }
    }
    return true;
  }
}

class AdvertisementEvaluation {
  const AdvertisementEvaluation({required this.matches, required this.reasons});

  final bool matches;
  final List<String> reasons;
}
