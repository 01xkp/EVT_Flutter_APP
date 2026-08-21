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
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.primary : null,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: selected ? theme.colorScheme.onPrimary : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      candidate.id,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: selected
                            ? theme.colorScheme.onPrimary.withValues(
                                alpha: 0.76,
                              )
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '${candidate.rssi} dBm',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? theme.colorScheme.onPrimary : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
