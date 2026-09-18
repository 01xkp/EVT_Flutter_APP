import 'dart:async';

import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:aipin/features/device_session/presentation/device_file_browser_page.dart';
import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/features/device_session/domain/device_file_import_progress.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'serializes imports and list refresh while an active transfer reports progress',
    (tester) async {
      final pending = Completer<LocalRecording>();
      final imported = <String>[];
      var listCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DeviceFileBrowserPage(
            onListFiles: ({required offset, required pageSize}) async {
              listCalls++;
              return offset == 0
                  ? const [
                      DeviceFile(name: 'first.ogg', nameSlot: [1], length: 10),
                      DeviceFile(name: 'second.ogg', nameSlot: [2], length: 10),
                    ]
                  : const [];
            },
            onImport: (file, {onProgress}) {
              imported.add(file.name);
              onProgress?.call(
                const DeviceFileImportProgress(received: 5, total: 10),
              );
              return pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存到 App').first);
      await tester.pump();
      expect(find.text('正在保存'), findsOneWidget);
      expect(find.text('保存到 App'), findsOneWidget);
      expect(find.text('50% · 5/10 B'), findsOneWidget);
      await tester.tap(find.text('保存到 App'));
      await tester.tap(find.byTooltip('刷新文件列表'));
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pump();
      expect(imported, ['first.ogg']);
      expect(listCalls, 2);
      pending.completeError(StateError('connection lost'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<AppButton>(find.byType(AppButton))
            .every((button) => button.onPressed != null),
        isTrue,
      );
      expect(find.text('正在保存'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets('saved file plays directly and deletion restores save action', (
    tester,
  ) async {
    var available = true;
    LocalRecording? played;
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceFileBrowserPage(
          onListFiles: ({required offset, required pageSize}) async =>
              offset == 0
              ? const [
                  DeviceFile(name: 'capture.ogg', nameSlot: [1], length: 10),
                ]
              : const [],
          onImport: (_, {onProgress}) async => _savedRecording(),
          onOpenRecording: (recording) async => played = recording,
          onOpenSavedRecordings: () async => available = false,
          isSavedRecordingAvailable: (_) async => available,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存到 App'));
    await tester.pumpAndSettle();
    expect(find.text('已保存到手机'), findsOneWidget);
    expect(find.text('保存到 App'), findsNothing);
    await tester.tap(find.text('播放'));
    await tester.pumpAndSettle();
    expect(played?.id, 'recording-1');
    await tester.tap(find.text('已保存录音'));
    await tester.pumpAndSettle();
    expect(find.text('已保存到手机'), findsNothing);
    expect(find.text('播放'), findsNothing);
    expect(find.text('保存到 App'), findsOneWidget);
  });

  testWidgets(
    'refresh keeps file actions disabled until refreshed list is ready',
    (tester) async {
      var refresh = false;
      final pending = Completer<List<DeviceFile>>();
      await tester.pumpWidget(
        MaterialApp(
          home: DeviceFileBrowserPage(
            onListFiles: ({required offset, required pageSize}) async {
              if (refresh && offset == 0) return pending.future;
              return offset == 0
                  ? const [
                      DeviceFile(
                        name: 'capture.ogg',
                        nameSlot: [1],
                        length: 10,
                      ),
                    ]
                  : const [];
            },
            onImport: (_, {onProgress}) =>
                throw StateError('must not import during refresh'),
            onMetadata: (_) =>
                throw StateError('must not read metadata during refresh'),
            onArchive: (_) =>
                throw StateError('must not archive during refresh'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      refresh = true;
      await tester.tap(find.text('刷新'));
      await tester.pump();
      final saveButton = tester.widget<AppButton>(
        find.widgetWithText(AppButton, '保存到 App'),
      );
      expect(saveButton.onPressed, isNull);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '元数据'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '归档并释放'))
            .onPressed,
        isNull,
      );
      expect(find.text('正在保存'), findsNothing);
      pending.complete(const []);
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'pending archive remains retryable when device file is already deleted',
    (tester) async {
      var pending = true;
      var retried = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DeviceFileBrowserPage(
            onListFiles: ({required offset, required pageSize}) async =>
                const [],
            onImport: (_, {onProgress}) =>
                throw StateError('must not download again'),
            onListPendingArchives: () async => pending
                ? const [
                    DeviceFile(
                      name: 'already-deleted.ogg',
                      nameSlot: [1],
                      length: 9,
                    ),
                  ]
                : const [],
            onRetryArchive: (_) async {
              retried++;
              pending = false;
              return '设备归档确认完成';
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('already-deleted.ogg'), findsOneWidget);
      await tester.tap(find.text('继续归档'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(retried, 0);
      await tester.tap(find.text('归档'));
      await tester.pumpAndSettle();
      expect(retried, 1);
      expect(find.text('already-deleted.ogg'), findsNothing);
      expect(find.text('设备归档确认完成'), findsOneWidget);
    },
  );

  testWidgets(
    'DVT archive requires confirmation and reports the real failure',
    (tester) async {
      var archiveCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DeviceFileBrowserPage(
            onListFiles: ({required offset, required pageSize}) async =>
                offset == 0
                ? const [
                    DeviceFile(name: 'capture.ogg', nameSlot: [1], length: 10),
                  ]
                : const [],
            onImport: (_, {onProgress}) => throw UnimplementedError(),
            onArchive: (_) async {
              archiveCalls++;
              throw StateError('云端未确认可靠保存');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('归档并释放'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(archiveCalls, 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(archiveCalls, 0);
      await tester.tap(find.text('归档并释放'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('归档'));
      await tester.pumpAndSettle();
      expect(archiveCalls, 1);
      expect(find.textContaining('云端未确认可靠保存'), findsOneWidget);
      expect(find.text('capture.ogg'), findsOneWidget);
    },
  );
  testWidgets('stops requesting file pages after the browser is disposed', (
    tester,
  ) async {
    final page = Completer<List<DeviceFile>>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceFileBrowserPage(
          onListFiles: ({required offset, required pageSize}) {
            calls++;
            return calls == 1 ? page.future : Future.value(const []);
          },
          onImport: (_, {onProgress}) => throw UnimplementedError(),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    page.complete(const [
      DeviceFile(name: 'first.ogg', nameSlot: [1], length: 10),
    ]);
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets('loads device files and imports a selected file', (tester) async {
    var calls = 0;
    var imported = false;
    LocalRecording? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceFileBrowserPage(
          onOpenRecording: (recording) async => opened = recording,
          onListFiles: ({required offset, required pageSize}) async {
            calls += 1;
            return offset == 0
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
    await tester.tap(find.text('保存到 App'));
    await tester.pumpAndSettle();

    expect(imported, isTrue);
    expect(calls, 4);
    expect(find.text('设备录音已保存到 App'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('已保存到手机'), findsOneWidget);
    expect(find.text('保存到 App'), findsNothing);
    await tester.tap(find.text('播放'));
    await tester.pumpAndSettle();
    expect(opened?.id, 'recording-1');
  });

  for (final destination in ['已保存录音', '播放']) {
    testWidgets(
      'allows saving again after deletion while visiting $destination',
      (tester) async {
        var available = false;
        var imports = 0;
        var opened = 0;
        final returned = Completer<void>();
        await tester.pumpWidget(
          MaterialApp(
            home: DeviceFileBrowserPage(
              onListFiles: ({required offset, required pageSize}) async =>
                  offset == 0
                  ? const [
                      DeviceFile(
                        name: 'capture.ogg',
                        nameSlot: [1],
                        length: 10,
                      ),
                    ]
                  : const [],
              onImport: (file, {onProgress}) async {
                imports++;
                available = true;
                return LocalRecording.saved(
                  id: 'recording-$imports',
                  title: file.name,
                  relativePath: 'recording-$imports.ogg',
                  createdAt: DateTime(2026, 1, 1),
                  completedAt: DateTime(2026, 1, 1),
                  duration: Duration.zero,
                  sizeBytes: 10,
                );
              },
              isSavedRecordingAvailable: (_) async => available,
              onOpenSavedRecordings: () {
                opened++;
                return returned.future;
              },
              onOpenRecording: (_) {
                opened++;
                return returned.future;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('保存到 App'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(destination));
        await tester.pump();
        expect(opened, 1);
        available = false;
        returned.complete();
        await tester.pumpAndSettle();

        expect(find.text('已保存到手机'), findsNothing);
        expect(find.text('保存到 App'), findsOneWidget);
        await tester.tap(find.text('保存到 App'));
        await tester.pumpAndSettle();
        expect(imports, 2);
        expect(find.text('已保存到手机'), findsOneWidget);
      },
    );
  }

  testWidgets('does not open a saved recording whose local file is missing', (
    tester,
  ) async {
    var available = true;
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceFileBrowserPage(
          onListFiles: ({required offset, required pageSize}) async =>
              offset == 0
              ? const [
                  DeviceFile(name: 'capture.ogg', nameSlot: [1], length: 10),
                ]
              : const [],
          onImport: (file, {onProgress}) async => LocalRecording.saved(
            id: 'recording-1',
            title: file.name,
            relativePath: 'recording-1.ogg',
            createdAt: DateTime(2026, 1, 1),
            completedAt: DateTime(2026, 1, 1),
            duration: Duration.zero,
            sizeBytes: 10,
          ),
          isSavedRecordingAvailable: (_) async => available,
          onOpenRecording: (_) async => opened = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存到 App'));
    await tester.pumpAndSettle();
    available = false;
    await tester.tap(find.text('播放'));
    await tester.pumpAndSettle();
    expect(opened, isFalse);
    expect(find.text('保存到 App'), findsOneWidget);
  });

  testWidgets('opens the saved-device-recording library from the file page', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceFileBrowserPage(
          onListFiles: ({required offset, required pageSize}) async => const [],
          onImport: (_, {onProgress}) => throw UnimplementedError(),
          onOpenSavedRecordings: () async {
            opened = true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('查看已保存录音'));

    expect(opened, isTrue);
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
    'reports a DVT file-import failure without claiming a checksum error',
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
              throw StateError('device transfer interrupted');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存到 App'));
      await tester.pumpAndSettle();

      expect(find.text('设备文件导入失败，请重试'), findsOneWidget);
      expect(find.text('导入失败，文件校验未通过，请重试'), findsNothing);
    },
  );
}

LocalRecording _savedRecording() => LocalRecording.saved(
  id: 'recording-1',
  title: 'capture.ogg',
  relativePath: 'recording-1.ogg',
  createdAt: DateTime(2026, 1, 1),
  completedAt: DateTime(2026, 1, 1),
  duration: const Duration(seconds: 1),
  sizeBytes: 10,
);
