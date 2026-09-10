import 'package:aipin/features/device_logs/data/platform_public_diagnostic_log_sink.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('aipin/public_diagnostic_logs');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'sends the canonical path and daily filename to Android MediaStore',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'mirrorCanonicalLog');
            expect(call.arguments, <String, Object?>{
              'sourcePath': '/app/files/logs/aipin-2026-09-01.log',
              'filename': 'aipin-2026-09-01.log',
              'requestPermission': false,
            });
            return <String, Object?>{
              'available': true,
              'relativePath': 'Download/AIPIN/logs/aipin-2026-09-01.log',
              'lastUpdatedAtEpochMilliseconds': 1788264000000,
            };
          });
      final sink = PlatformPublicDiagnosticLogSink(isAndroid: () => true);

      final status = await sink.mirrorCanonicalFile(
        sourcePath: '/app/files/logs/aipin-2026-09-01.log',
        filename: 'aipin-2026-09-01.log',
      );

      expect(status.available, isTrue);
      expect(status.relativePath, 'Download/AIPIN/logs/aipin-2026-09-01.log');
    },
  );

  test(
    'sends the canonical path and daily filename to iOS Documents',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'mirrorCanonicalLog');
            expect(call.arguments, <String, Object?>{
              'sourcePath': '/app/files/logs/aipin-2026-09-01.log',
              'filename': 'aipin-2026-09-01.log',
              'requestPermission': false,
            });
            return <String, Object?>{
              'available': true,
              'relativePath': 'Documents/AIPIN/logs/aipin-2026-09-01.log',
              'lastUpdatedAtEpochMilliseconds': 1788264000000,
            };
          });
      final sink = PlatformPublicDiagnosticLogSink(
        isAndroid: () => false,
        isIOS: () => true,
      );

      final status = await sink.mirrorCanonicalFile(
        sourcePath: '/app/files/logs/aipin-2026-09-01.log',
        filename: 'aipin-2026-09-01.log',
      );

      expect(status.available, isTrue);
      expect(status.relativePath, 'Documents/AIPIN/logs/aipin-2026-09-01.log');
    },
  );

  test('marks a user-initiated log export as permission eligible', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.arguments, <String, Object?>{
            'sourcePath': '/app/files/logs/aipin-2026-09-01.log',
            'filename': 'aipin-2026-09-01.log',
            'requestPermission': true,
          });
          return <String, Object?>{
            'available': false,
            'failureCode': 'legacy_permission_denied',
          };
        });
    final sink = PlatformPublicDiagnosticLogSink(isAndroid: () => true);

    final status = await sink.mirrorCanonicalFile(
      sourcePath: '/app/files/logs/aipin-2026-09-01.log',
      filename: 'aipin-2026-09-01.log',
      requestPermission: true,
    );

    expect(status.available, isFalse);
    expect(status.failureCode, 'legacy_permission_denied');
  });

  test(
    'uses a no-op status outside Android and iOS without invoking a channel',
    () async {
      var invoked = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            invoked = true;
            return <String, Object?>{};
          });
      final sink = PlatformPublicDiagnosticLogSink(
        isAndroid: () => false,
        isIOS: () => false,
      );

      final status = await sink.mirrorCanonicalFile(
        sourcePath: '/app/files/logs/aipin-2026-09-01.log',
        filename: 'aipin-2026-09-01.log',
      );

      expect(status.available, isFalse);
      expect(status.relativePath, isNull);
      expect(invoked, isFalse);
    },
  );
}
