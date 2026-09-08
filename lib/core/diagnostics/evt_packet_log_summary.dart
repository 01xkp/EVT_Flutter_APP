import 'package:flutter/foundation.dart';

/// Produces a deliberately small, safe representation of an EVT wire frame.
///
/// EVT carries device names, file names, security codes, and audio bytes on
/// the same response stream as ordinary control messages. This helper is the
/// only place where a command-level logger may turn wire bytes into text. It
/// exposes complete bytes only for fixed-shape control frames whose V1.5
/// payloads are numeric configuration or state values.
class EvtPacketLogSummary {
  const EvtPacketLogSummary._({
    required this.byteLength,
    required this.command,
    required this.contentLength,
    required this.frameSummary,
    required this.wireSummary,
  });

  static const _frameHead = 0xED;
  static const _omittedSummaries = <String>{
    'evt_malformed_content_omitted',
    'evt_authentication_content_redacted',
    'evt_sensitive_content_omitted',
    'evt_unrecognized_content_omitted',
  };
  static final _frameSummaryPattern = RegExp(
    r'^evt_control cmd=(0x[0-9A-F]{2}) content=(empty|[0-9A-F]{2}(?: [0-9A-F]{2}){0,17})$',
  );
  static final _wireSummaryPattern = RegExp(
    r'^evt_control cmd=(0x[0-9A-F]{2}) wire=([0-9A-F]{2}(?: [0-9A-F]{2}){5,20})$',
  );
  static final _authenticationFrameSummaryPattern = RegExp(
    r'^evt_authentication cmd=0x09 action=0x0[0-2] security_code=redacted$',
  );
  static final _authenticationWireSummaryPattern = RegExp(
    r'^evt_authentication cmd=0x09 action=(0x0[0-2]) wire=ED 0A 00 09 (0[0-2]) \*\* \*\* \*\* \*\* \*\* \*\* [0-9A-F]{2} [0-9A-F]{2}$',
  );

  /// The field map is intentionally made of scalars only. In particular, it
  /// never returns the raw [List<int>] supplied by BLE.
  Map<String, Object?> get fields => <String, Object?>{
    'bytes': byteLength,
    if (command != null) 'command': command,
    if (contentLength != null) 'content_length': contentLength,
    'frame_summary': frameSummary,
    'wire_summary': wireSummary,
  };

  final int byteLength;
  final String? command;
  final int? contentLength;
  final String frameSummary;
  final String wireSummary;

  /// Exposes a complete wire frame only in a Debug build. The diagnostic
  /// sanitizer independently rejects this field in non-Debug builds.
  static Map<String, Object?> debugRawPacketFields(
    List<int> bytes, {
    bool includeRawData = kDebugMode,
  }) => includeRawData
      ? <String, Object?>{'raw_packet_hex': _hexBytes(bytes)}
      : const <String, Object?>{};

  /// Returns whether [value] is a summary created by this class and can enter
  /// a persistent diagnostic. Callers cannot use this as a general hex dump:
  /// both the command and the fixed V1.5 payload shape are checked.
  static bool isPersistableSummary({
    required String key,
    required String value,
  }) {
    if (_omittedSummaries.contains(value)) {
      return true;
    }
    if (key == 'frame_summary' &&
        _authenticationFrameSummaryPattern.hasMatch(value)) {
      return true;
    }
    if (key == 'wire_summary') {
      final authenticationMatch = _authenticationWireSummaryPattern.firstMatch(
        value,
      );
      if (authenticationMatch != null) {
        return authenticationMatch.group(1) ==
            '0x${authenticationMatch.group(2)}';
      }
    }
    final match = switch (key) {
      'frame_summary' => _frameSummaryPattern.firstMatch(value),
      'wire_summary' => _wireSummaryPattern.firstMatch(value),
      _ => null,
    };
    if (match == null) {
      return false;
    }
    final command = int.tryParse(match.group(1)!.substring(2), radix: 16);
    if (command == null) {
      return false;
    }

    if (key == 'frame_summary') {
      final content = match.group(2)!;
      final contentLength = content == 'empty' ? 0 : content.split(' ').length;
      return _isSafeControlFrame(command, contentLength);
    }

    final bytes = match
        .group(2)!
        .split(' ')
        .map((value) => int.tryParse(value, radix: 16))
        .toList(growable: false);
    if (bytes.any((value) => value == null) ||
        bytes.length < 6 ||
        bytes.first != _frameHead ||
        bytes[3] != command) {
      return false;
    }
    final declaredLength = bytes[1]! | (bytes[2]! << 8);
    if (declaredLength < 3 || bytes.length != declaredLength + 3) {
      return false;
    }
    return _isSafeControlFrame(command, declaredLength - 3);
  }

  /// Creates a safe summary without retaining the source packet.
  ///
  /// The packet shape is checked before a command can be considered for the
  /// control-frame allowlist. A malformed or future frame remains observable
  /// through its size and command code, but none of its content is rendered.
  factory EvtPacketLogSummary.fromWireBytes(List<int> bytes) {
    final byteLength = bytes.length;
    if (byteLength < 6 || bytes.first != _frameHead) {
      return EvtPacketLogSummary._omitted(
        byteLength: byteLength,
        frameSummary: 'evt_malformed_content_omitted',
      );
    }

    final declaredLength = bytes[1] | (bytes[2] << 8);
    final commandValue = bytes[3];
    final command = _hex(commandValue);
    if (declaredLength < 3 || byteLength != declaredLength + 3) {
      return EvtPacketLogSummary._omitted(
        byteLength: byteLength,
        command: command,
        frameSummary: 'evt_malformed_content_omitted',
      );
    }

    final contentLength = declaredLength - 3;
    if (_isAuthenticationRequest(commandValue)) {
      if (contentLength == 7 && bytes[4] <= 2) {
        final action = _hex(bytes[4]);
        return EvtPacketLogSummary._(
          byteLength: byteLength,
          command: command,
          contentLength: contentLength,
          frameSummary:
              'evt_authentication cmd=0x09 action=$action security_code=redacted',
          wireSummary:
              'evt_authentication cmd=0x09 action=$action '
              'wire=ED 0A 00 09 ${_hexByte(bytes[4])} ** ** ** ** ** ** '
              '${_hexByte(bytes[byteLength - 2])} ${_hexByte(bytes[byteLength - 1])}',
        );
      }
      return EvtPacketLogSummary._omitted(
        byteLength: byteLength,
        command: command,
        contentLength: contentLength,
        frameSummary: 'evt_authentication_content_redacted',
      );
    }
    if (_containsDeviceFileOrAudioContent(commandValue)) {
      return EvtPacketLogSummary._omitted(
        byteLength: byteLength,
        command: command,
        contentLength: contentLength,
        frameSummary: 'evt_sensitive_content_omitted',
      );
    }
    if (!_isSafeControlFrame(commandValue, contentLength)) {
      return EvtPacketLogSummary._omitted(
        byteLength: byteLength,
        command: command,
        contentLength: contentLength,
        frameSummary: 'evt_unrecognized_content_omitted',
      );
    }

    final contentStart = 4;
    final contentEnd = contentStart + contentLength;
    final content = bytes.sublist(contentStart, contentEnd);
    return EvtPacketLogSummary._(
      byteLength: byteLength,
      command: command,
      contentLength: contentLength,
      frameSummary: 'evt_control cmd=$command content=${_hexBytes(content)}',
      wireSummary: 'evt_control cmd=$command wire=${_hexBytes(bytes)}',
    );
  }

  factory EvtPacketLogSummary._omitted({
    required int byteLength,
    String? command,
    int? contentLength,
    required String frameSummary,
  }) => EvtPacketLogSummary._(
    byteLength: byteLength,
    command: command,
    contentLength: contentLength,
    frameSummary: frameSummary,
    wireSummary: frameSummary,
  );

  /// Only the request contains the six-byte security code. Its safe summary
  /// preserves the V1.5 header, action and CRC while masking all six code
  /// bytes. The fixed one-byte `0x89` result remains fully visible and is the
  /// decisive field when debugging an FA19 indication that did or did not
  /// reach Flutter.
  static bool _isAuthenticationRequest(int command) => command == 0x09;

  static bool _containsDeviceFileOrAudioContent(int command) =>
      switch (command) {
        // 0x81 includes the device code and user-visible device name.
        0x01 ||
        0x81 ||
        // 0x22/0xA2 carry file slots; 0x23 carries file names and audio chunks.
        0x22 ||
        0xA2 ||
        0x23 => true,
        _ => false,
      };

  /// V1.5's fixed-shape numeric control frames. Unknown subcommands or a
  /// changed length intentionally fail closed and do not render their bytes.
  static bool _isSafeControlFrame(int command, int contentLength) =>
      switch (command) {
        // Configuration request / acknowledgement.
        0x02 => contentLength == 12,
        0x82 => contentLength == 1 || contentLength == 4,
        // Status/configuration and recording control.
        0x06 => contentLength == 1 || contentLength == 3,
        0x86 => contentLength == 3 || contentLength == 8,
        0x07 => contentLength == 1,
        0x87 => contentLength == 1 || contentLength == 8,
        // V1 0x09 response: Result:u8, where 0 means rejected and 1 means
        // accepted. It contains no security code or device identifier.
        0x89 => contentLength == 1,
        // Battery, storage and compatibility file-count values are numeric.
        0x11 => contentLength == 0,
        0x91 => contentLength == 3,
        0x85 => contentLength == 8,
        0x21 => contentLength == 0,
        0xA1 => contentLength == 2,
        _ => false,
      };

  static String _hex(int value) => '0x${_hexByte(value)}';

  static String _hexByte(int value) =>
      value.toRadixString(16).padLeft(2, '0').toUpperCase();

  static String _hexBytes(List<int> bytes) => bytes.isEmpty
      ? 'empty'
      : bytes
            .map(
              (value) => value.toRadixString(16).padLeft(2, '0').toUpperCase(),
            )
            .join(' ');
}
