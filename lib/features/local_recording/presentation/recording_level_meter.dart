import 'package:aipin/core/design_system/evt_theme.dart';
import 'package:flutter/material.dart';

class RecordingLevelMeter extends StatelessWidget {
  const RecordingLevelMeter({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final level = value.clamp(0.0, 1.0);
    return SizedBox(
      height: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var index = 0; index < 9; index += 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AnimatedContainer(
                duration: EvtTheme.motionDuration,
                width: 4,
                height: 8 + level * (index.isEven ? 28 : 20),
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }
}
