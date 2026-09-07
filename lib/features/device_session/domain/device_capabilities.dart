class DeviceCapabilities {
  const DeviceCapabilities({
    required this.protocolVersion,
    this.supportsRealtimeAudio = false,
    this.supportsDualOta = false,
  });

  final int protocolVersion;
  final bool supportsRealtimeAudio;
  final bool supportsDualOta;
}
