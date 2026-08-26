import 'package:aipin/app/branding/aipin_brand.dart';
import 'package:flutter/material.dart';

class AipinVoicePageMark extends StatelessWidget {
  const AipinVoicePageMark({super.key, this.size = 128});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _AipinVoicePageMarkPainter(),
    );
  }
}

class _AipinVoicePageMarkPainter extends CustomPainter {
  static const _referenceSize = 128.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / _referenceSize;
    final paint = Paint()
      ..color = AipinBrand.markColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final waveform = Path()
      ..moveTo(22 * scale, 68 * scale)
      ..cubicTo(
        31 * scale,
        68 * scale,
        33 * scale,
        50 * scale,
        42 * scale,
        50 * scale,
      )
      ..cubicTo(
        51 * scale,
        50 * scale,
        53 * scale,
        82 * scale,
        62 * scale,
        82 * scale,
      )
      ..cubicTo(
        71 * scale,
        82 * scale,
        72 * scale,
        39 * scale,
        81 * scale,
        39 * scale,
      )
      ..cubicTo(
        90 * scale,
        39 * scale,
        91 * scale,
        70 * scale,
        100 * scale,
        70 * scale,
      );
    final page = Path()
      ..moveTo(27 * scale, 88 * scale)
      ..lineTo(91 * scale, 88 * scale)
      ..cubicTo(
        101 * scale,
        88 * scale,
        107 * scale,
        82 * scale,
        107 * scale,
        72 * scale,
      )
      ..lineTo(107 * scale, 43 * scale);

    canvas.drawPath(waveform, paint);
    canvas.drawPath(page, paint);
  }

  @override
  bool shouldRepaint(covariant _AipinVoicePageMarkPainter oldDelegate) => false;
}
