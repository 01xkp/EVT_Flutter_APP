import 'package:evt_ble_app/core/design_system/widgets/app_surface_card.dart';
import 'package:evt_ble_app/features/device_discovery/domain/device_candidate.dart';
import 'package:flutter/material.dart';

class DeviceCandidateRow extends StatelessWidget {
  const DeviceCandidateRow({
    super.key,
    required this.candidate,
    required this.selected,
    required this.onTap,
  });

  final DeviceCandidate candidate;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      onTap: onTap,
      selected: selected,
      child: Row(
        children: [
          const Icon(Icons.bluetooth_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              candidate.name,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Text(
            _signalLabel(candidate.rssi),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      ),
    );
  }

  String _signalLabel(int rssi) => switch (rssi) {
    >= -55 => '信号良好',
    >= -70 => '信号一般',
    _ => '信号较弱',
  };
}
