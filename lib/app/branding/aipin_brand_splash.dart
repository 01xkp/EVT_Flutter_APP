import 'package:aipin/app/branding/aipin_brand.dart';
import 'package:aipin/app/branding/aipin_voice_page_mark.dart';
import 'package:flutter/material.dart';

class AipinBrandSplash extends StatelessWidget {
  const AipinBrandSplash({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      key: const ValueKey('aipinBrandSplash'),
      backgroundColor: AipinBrand.launchCanvas,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AipinVoicePageMark(size: 112),
            const SizedBox(height: 20),
            Text(
              AipinBrand.displayName,
              style: textTheme.titleLarge?.copyWith(
                color: AipinBrand.markColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AipinBrand.tagline,
              style: textTheme.bodyMedium?.copyWith(
                color: AipinBrand.markColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
