class DeviceFile {
  const DeviceFile({
    required this.name,
    required this.nameSlot,
    required this.length,
  });

  final String name;
  final List<int> nameSlot;
  final int length;
}
