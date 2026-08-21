import 'dart:io';

import 'package:evt_ble_app/features/local_recording/domain/recording_background_port.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class RecordingBackgroundException implements Exception {
  const RecordingBackgroundException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NoopRecordingBackgroundService implements RecordingBackgroundPort {
  const NoopRecordingBackgroundService();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> updateElapsed(Duration elapsed) async {}
}

class ForegroundRecordingService implements RecordingBackgroundPort {
  bool _initialized = false;
  bool _started = false;

  @override
  Future<void> start() async {
    if (!Platform.isAndroid) {
      return;
    }
    _initialize();
    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (await FlutterForegroundTask.isRunningService) {
      _started = true;
      return;
    }
    final result = await FlutterForegroundTask.startService(
      serviceId: 7021,
      serviceTypes: const [ForegroundServiceTypes.microphone],
      notificationTitle: '正在本机录音',
      notificationText: '00:00:00',
      callback: startRecordingForegroundTask,
    );
    _throwForFailure(result);
    _started = true;
  }

  @override
  Future<void> updateElapsed(Duration elapsed) async {
    if (!Platform.isAndroid || !_started) {
      return;
    }
    final result = await FlutterForegroundTask.updateService(
      notificationText: _formatElapsed(elapsed),
    );
    _throwForFailure(result);
  }

  @override
  Future<void> stop() async {
    if (!Platform.isAndroid || !_started) {
      return;
    }
    try {
      if (await FlutterForegroundTask.isRunningService) {
        _throwForFailure(await FlutterForegroundTask.stopService());
      }
    } finally {
      _started = false;
    }
  }

  void _initialize() {
    if (_initialized) {
      return;
    }
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'evt_local_recording',
        channelName: '本机录音',
        channelDescription: '录音进行时保持麦克风服务运行。',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowAutoRestart: false,
        stopWithTask: true,
      ),
    );
    _initialized = true;
  }

  void _throwForFailure(ServiceRequestResult result) {
    if (result case ServiceRequestFailure(:final error)) {
      throw RecordingBackgroundException(error.toString());
    }
  }

  String _formatElapsed(Duration value) {
    String part(int item) => item.toString().padLeft(2, '0');
    return '${part(value.inHours)}:${part(value.inMinutes.remainder(60))}:${part(value.inSeconds.remainder(60))}';
  }
}

@pragma('vm:entry-point')
void startRecordingForegroundTask() {
  FlutterForegroundTask.setTaskHandler(_RecordingForegroundTaskHandler());
}

class _RecordingForegroundTaskHandler extends TaskHandler {
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
}
