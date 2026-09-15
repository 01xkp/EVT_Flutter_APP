import 'dart:typed_data';

import 'package:aipin/core/protocol/crc16.dart';

/// Result of feeding one native BLE value into [EvtFrameAssembler].
///
/// A BLE characteristic stream is allowed to split a business frame across
/// values or combine several business frames in one value.  The assembler
/// keeps only the incomplete tail and returns complete, CRC-validated frames.
/// Rejected candidates are returned for diagnostics; callers should not route
/// them to business code.
class EvtFrameAssemblyResult {
  const EvtFrameAssemblyResult({
    required this.frames,
    required this.rejectedFrames,
    required this.discardedByteCount,
    required this.bufferedByteCount,
  });

  final List<Uint8List> frames;
  final List<Uint8List> rejectedFrames;
  final int discardedByteCount;
  final int bufferedByteCount;
}

/// Incrementally reconstructs V1.6 EVT business frames from BLE values.
///
/// Wire format: `ED | Length(u16 LE) | CMD | Content | CRC16(u16 LE)`.
/// Length includes CMD, Content and CRC, so the complete frame has
/// `Length + 3` bytes.  The parser is deliberately independent of the codec
/// so transport consumers can share exactly the same framing behavior.
class EvtFrameAssembler {
  EvtFrameAssembler({this.maxLengthField = 0xFFFF})
    : assert(maxLengthField >= 3 && maxLengthField <= 0xFFFF);

  static const head = 0xED;
  static const minimumLengthField = 3;

  final int maxLengthField;
  final List<int> _buffer = <int>[];

  int get bufferedByteCount => _buffer.length;

  /// Adds one native characteristic value and returns all complete frames
  /// available after the value is appended.
  EvtFrameAssemblyResult add(Iterable<int> bytes) {
    for (final byte in bytes) {
      if (byte < 0 || byte > 0xFF) {
        throw RangeError.range(byte, 0, 0xFF, 'byte');
      }
      _buffer.add(byte);
    }

    final frames = <Uint8List>[];
    final rejectedFrames = <Uint8List>[];
    var discardedByteCount = 0;

    while (_buffer.isNotEmpty) {
      final headIndex = _buffer.indexOf(head);
      if (headIndex < 0) {
        discardedByteCount += _buffer.length;
        _buffer.clear();
        break;
      }
      if (headIndex > 0) {
        discardedByteCount += headIndex;
        _buffer.removeRange(0, headIndex);
      }
      if (_buffer.length < 3) {
        break;
      }

      final declaredLength = _buffer[1] | (_buffer[2] << 8);
      if (declaredLength < minimumLengthField ||
          declaredLength > maxLengthField) {
        rejectedFrames.add(
          Uint8List.fromList(
            _buffer.sublist(0, _buffer.length < 3 ? _buffer.length : 3),
          ),
        );
        _buffer.removeAt(0);
        continue;
      }

      final totalLength = declaredLength + 3;
      if (_buffer.length < totalLength) {
        // FileData is arbitrary binary content and can itself contain an
        // entire CRC-valid ED frame. Honor the outer length until its CRC
        // can be checked; searching inside a partial payload corrupts files
        // and can misroute file bytes as an authentication/state response.
        // Impossible lengths are rejected above using maxLengthField. A
        // stalled partial frame is discarded when its connection is reset.
        break;
      }

      final candidate = Uint8List.fromList(_buffer.sublist(0, totalLength));
      if (_hasValidCrc(candidate, declaredLength)) {
        _buffer.removeRange(0, totalLength);
        frames.add(candidate);
        continue;
      }

      // Keep the rejected candidate for a bounded diagnostic record, then
      // advance by one byte rather than the declared length.  This permits a
      // valid frame immediately following a CRC-corrupted frame to survive.
      rejectedFrames.add(candidate);
      _buffer.removeAt(0);
    }

    return EvtFrameAssemblyResult(
      frames: List<Uint8List>.unmodifiable(frames),
      rejectedFrames: List<Uint8List>.unmodifiable(rejectedFrames),
      discardedByteCount: discardedByteCount,
      bufferedByteCount: _buffer.length,
    );
  }

  /// Clears an incomplete frame.  Call this when a GATT session is closed so
  /// bytes from an old connection can never prefix a new connection's frame.
  void reset() => _buffer.clear();

  static bool _hasValidCrc(Uint8List frame, int declaredLength) {
    final contentEnd = 4 + declaredLength - minimumLengthField;
    if (contentEnd + 2 != frame.length || contentEnd < 4) {
      return false;
    }
    final expectedCrc = frame[contentEnd] | (frame[contentEnd + 1] << 8);
    final actualCrc = Crc16CcittFalse.calculate(frame.sublist(3, contentEnd));
    return actualCrc == expectedCrc;
  }
}
