import 'dart:io';

import 'package:aipin/features/local_recording/domain/local_recording.dart';

/// Keeps platform media support separate from the EVT BLE file-transfer
/// contract. The device can transfer Ogg/Opus to either platform, but iOS
/// AVFoundation cannot decode it for local playback.
abstract final class DeviceRecordingPlaybackSupport {
  static bool canPlay(
    LocalRecording recording, {
    bool? isIOS,
  }) {
    if (!recording.isPlayable) {
      return false;
    }
    final onIOS = isIOS ?? Platform.isIOS;
    return !onIOS || !_isOgg(recording.relativePath);
  }

  static String unavailableMessage(
    LocalRecording recording, {
    bool? isIOS,
  }) {
    final onIOS = isIOS ?? Platform.isIOS;
    if (onIOS && _isOgg(recording.relativePath)) {
      return '该设备录音已保存，但当前 iOS 不支持直接播放 Ogg/Opus 文件。';
    }
    return '这条设备录音暂时无法播放。';
  }

  static bool _isOgg(String relativePath) =>
      relativePath.trim().toLowerCase().endsWith('.ogg');
}
