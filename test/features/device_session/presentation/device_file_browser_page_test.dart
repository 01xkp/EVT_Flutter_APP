import 'package:aipin/features/device_session/presentation/device_file_browser_page.dart';
import 'package:aipin/features/device_session/data/device_file_import_service.dart';
import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/features/device_session/domain/archive_gateway.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loads device files and imports a selected file', (tester) async {
    var calls = 0;
    var imported = false;
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceFileBrowserPage(
          onListFiles: ({required offset, required pageSize}) async {
            calls += 1;
            return calls == 1
                ? const [
                    DeviceFile(name: 'capture.ogg', nameSlot: [1], length: 10),
                  ]
                : const [];
          },
          onImport: (file, {onProgress}) async {
            imported = true;
            onProgress?.call(
              const DeviceFileImportProgress(received: 10, total: 10),
            );
            return LocalRecording.saved(
              id: 'recording-1',
              title: file.name,
              relativePath: 'recording-1.m4a',
              createdAt: DateTime(2026, 1, 1),
              completedAt: DateTime(2026, 1, 1),
              duration: const Duration(seconds: 1),
              sizeBytes: 10,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('capture.ogg'), findsOneWidget);
    await tester.tap(find.text('导入到记录'));
    await tester.pumpAndSettle();

    expect(imported, isTrue);
    expect(find.text('设备录音已导入记录'), findsOneWidget);
  });

  testWidgets('continues pagination until the firmware returns Count zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceFileBrowserPage(
          onListFiles: ({required offset, required pageSize}) async =>
              switch (offset) {
                0 => const [
                  DeviceFile(name: 'first.ogg', nameSlot: [1], length: 10),
                ],
                1 => const [
                  DeviceFile(name: 'second.ogg', nameSlot: [2], length: 10),
                ],
                _ => const [],
              },
          onImport: (_, {onProgress}) => throw UnimplementedError(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('first.ogg'), findsOneWidget);
    expect(find.text('second.ogg'), findsOneWidget);
  });

  testWidgets('stops a malformed list that repeats a file slot', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceFileBrowserPage(
          onListFiles: ({required offset, required pageSize}) async {
            calls += 1;
            if (calls > 2) {
              throw StateError('malformed pagination continued');
            }
            return const [
              DeviceFile(name: 'repeated.ogg', nameSlot: [1], length: 10),
            ];
          },
          onImport: (_, {onProgress}) => throw UnimplementedError(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('设备录音列表暂时不可读取，请重试'), findsOneWidget);
  });

  testWidgets(
    'reports archive configuration failure without claiming a checksum error',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DeviceFileBrowserPage(
            onListFiles: ({required offset, required pageSize}) async =>
                calls++ == 0
                ? const [
                    DeviceFile(name: 'capture.ogg', nameSlot: [1], length: 10),
                  ]
                : const [],
            onImport: (file, {onProgress}) async {
              throw const ArchiveGatewayUnavailableException();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('导入到记录'));
      await tester.pumpAndSettle();

      expect(find.text('云端归档服务未配置，设备文件已保留'), findsOneWidget);
      expect(find.text('导入失败，文件校验未通过，请重试'), findsNothing);
    },
  );
}
