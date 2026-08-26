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

  // Temporarily accept every advertisement during device commissioning.
  AdvertisementEvaluation evaluate(DeviceCandidate candidate) =>
      const AdvertisementEvaluation(matches: true, reasons: []);
}

class AdvertisementEvaluation {
  const AdvertisementEvaluation({required this.matches, required this.reasons});

  final bool matches;
  final List<String> reasons;
}
