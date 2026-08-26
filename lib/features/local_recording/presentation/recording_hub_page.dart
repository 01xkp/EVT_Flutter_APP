import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:aipin/core/design_system/widgets/app_surface_card.dart';
import 'package:flutter/material.dart';

class RecordingHubPage extends StatelessWidget {
  const RecordingHubPage({
    super.key,
    required this.isHardwareObservable,
    this.onStartLocal,
    this.onOpenLibrary,
    this.onOpenHardware,
  });

  final bool isHardwareObservable;
  final VoidCallback? onStartLocal;
  final VoidCallback? onOpenLibrary;
  final VoidCallback? onOpenHardware;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('录音'),
        actions: [
          IconButton(
            tooltip: '查看本机录音',
            onPressed: onOpenLibrary,
            icon: const Icon(Icons.library_music_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth > 600 ? 520 : double.infinity,
              ),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text('本机录音', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('无需连接设备', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 20),
                  AppButton.primary(
                    label: '开始本机录音',
                    onPressed: onStartLocal,
                    icon: Icons.mic_none_outlined,
                  ),
                  const SizedBox(height: 28),
                  AppSurfaceCard(
                    onTap: isHardwareObservable ? onOpenHardware : null,
                    child: Row(
                      children: [
                        const Icon(Icons.memory_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '设备录音状态',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isHardwareObservable ? '可在设备详情查看' : '暂时无法获取',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (isHardwareObservable)
                          const Icon(Icons.arrow_forward),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
