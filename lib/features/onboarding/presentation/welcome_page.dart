import 'package:aipin/app/branding/aipin_brand.dart';
import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:flutter/material.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, required this.onConnectDevice});

  final VoidCallback onConnectDevice;

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
                    '连接设备后开始 DVT 联调',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const Spacer(flex: 2),
                  AppButton.primary(
                    label: '连接我的设备',
                    onPressed: onConnectDevice,
                    icon: Icons.bluetooth_outlined,
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
