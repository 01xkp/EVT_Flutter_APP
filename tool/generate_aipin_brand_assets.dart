import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

final _canvas = img.ColorRgba8(240, 244, 248, 255);
final _mark = img.ColorRgba8(25, 33, 43, 255);
const _referenceSize = 128.0;
const _sourceSize = 4096;
const _brandLaunchContents = '''{
  "images": [
    {"idiom":"universal","filename":"brand_launch.png","scale":"1x"},
    {"idiom":"universal","filename":"brand_launch@2x.png","scale":"2x"},
    {"idiom":"universal","filename":"brand_launch@3x.png","scale":"3x"}
  ],
  "info": {"version":1,"author":"xcode"}
}
''';

void main() {
  final source = _renderMark(_sourceSize);

  _writePng('assets/branding/aipin_voice_page_icon.png', source, 1024);
  for (final output in _androidOutputs) {
    _writePng(output.path, source, output.size);
  }

  final appIconContents = File(
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json',
  );
  final appIconImages =
      jsonDecode(appIconContents.readAsStringSync())['images'] as List<dynamic>;
  for (final entry in appIconImages.cast<Map<String, dynamic>>()) {
    final filename = entry['filename'] as String?;
    if (filename == null) {
      continue;
    }
    final points = double.parse((entry['size'] as String).split('x').first);
    final scale = int.parse((entry['scale'] as String).replaceAll('x', ''));
    _writePng(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/$filename',
      source,
      (points * scale).round(),
    );
  }

  File('ios/Runner/Assets.xcassets/BrandLaunch.imageset/Contents.json')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(_brandLaunchContents);
  for (final output in _brandLaunchOutputs) {
    _writePng(output.path, source, output.size);
  }
}

img.Image _renderMark(int size) {
  final image = img.Image(width: size, height: size, numChannels: 4)
    ..clear(_canvas);
  final scale = size / _referenceSize;
  final strokeWidth = (6 * scale).round();

  final waveform = <_Point>[
    _point(22, 68, scale),
    ..._cubic(
      _point(22, 68, scale),
      _point(31, 68, scale),
      _point(33, 50, scale),
      _point(42, 50, scale),
    ),
    ..._cubic(
      _point(42, 50, scale),
      _point(51, 50, scale),
      _point(53, 82, scale),
      _point(62, 82, scale),
    ),
    ..._cubic(
      _point(62, 82, scale),
      _point(71, 82, scale),
      _point(72, 39, scale),
      _point(81, 39, scale),
    ),
    ..._cubic(
      _point(81, 39, scale),
      _point(90, 39, scale),
      _point(91, 70, scale),
      _point(100, 70, scale),
    ),
  ];
  final page = <_Point>[
    _point(27, 88, scale),
    _point(91, 88, scale),
    ..._cubic(
      _point(91, 88, scale),
      _point(101, 88, scale),
      _point(107, 82, scale),
      _point(107, 72, scale),
    ),
    _point(107, 43, scale),
  ];

  _drawRoundedPath(image, waveform, strokeWidth);
  _drawRoundedPath(image, page, strokeWidth);
  return image;
}

void _drawRoundedPath(img.Image image, List<_Point> points, int strokeWidth) {
  final radius = strokeWidth ~/ 2;
  for (final point in points) {
    img.fillCircle(
      image,
      x: point.x.round(),
      y: point.y.round(),
      radius: radius,
      color: _mark,
    );
  }
  for (var index = 1; index < points.length; index++) {
    final start = points[index - 1];
    final end = points[index];
    img.drawLine(
      image,
      x1: start.x.round(),
      y1: start.y.round(),
      x2: end.x.round(),
      y2: end.y.round(),
      color: _mark,
      thickness: strokeWidth,
      antialias: true,
    );
  }
}

List<_Point> _cubic(_Point start, _Point first, _Point second, _Point end) {
  const segments = 64;
  return List.generate(segments, (index) {
    final t = (index + 1) / segments;
    final inverse = 1 - t;
    return _Point(
      math.pow(inverse, 3) * start.x +
          3 * math.pow(inverse, 2) * t * first.x +
          3 * inverse * math.pow(t, 2) * second.x +
          math.pow(t, 3) * end.x,
      math.pow(inverse, 3) * start.y +
          3 * math.pow(inverse, 2) * t * first.y +
          3 * inverse * math.pow(t, 2) * second.y +
          math.pow(t, 3) * end.y,
    );
  });
}

_Point _point(double x, double y, double scale) => _Point(x * scale, y * scale);

void _writePng(String path, img.Image source, int size) {
  final file = File(path)..parent.createSync(recursive: true);
  final image = img.copyResize(
    source,
    width: size,
    height: size,
    interpolation: img.Interpolation.cubic,
  );
  file.writeAsBytesSync(img.encodePng(image));
}

class _Point {
  const _Point(this.x, this.y);

  final double x;
  final double y;
}

class _AssetOutput {
  const _AssetOutput(this.path, this.size);

  final String path;
  final int size;
}

const _androidOutputs = [
  _AssetOutput('android/app/src/main/res/mipmap-mdpi/ic_launcher.png', 48),
  _AssetOutput('android/app/src/main/res/mipmap-hdpi/ic_launcher.png', 72),
  _AssetOutput('android/app/src/main/res/mipmap-xhdpi/ic_launcher.png', 96),
  _AssetOutput('android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png', 144),
  _AssetOutput('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png', 192),
];

const _brandLaunchOutputs = [
  _AssetOutput(
    'ios/Runner/Assets.xcassets/BrandLaunch.imageset/brand_launch.png',
    112,
  ),
  _AssetOutput(
    'ios/Runner/Assets.xcassets/BrandLaunch.imageset/brand_launch@2x.png',
    224,
  ),
  _AssetOutput(
    'ios/Runner/Assets.xcassets/BrandLaunch.imageset/brand_launch@3x.png',
    336,
  ),
];
