import 'package:aipin/app/branding/aipin_brand.dart';
import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:flutter/material.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({
    super.key,
    required this.onConnectDevice,
    required this.onUseLocalRecording,
  });

  final VoidCallback onConnectDevice;
  final VoidCallback onUseLocalRecording;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  Text(
                    AipinBrand.displayName,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '从连接设备或本机录音开始',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const Spacer(flex: 2),
                  AppButton.primary(
                    label: '连接我的设备',
                    onPressed: onConnectDevice,
                    icon: Icons.bluetooth_outlined,
                  ),
                  const SizedBox(height: 12),
                  AppButton.secondary(
                    label: '先用本机录音',
                    onPressed: onUseLocalRecording,
                    icon: Icons.mic_none_outlined,
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
