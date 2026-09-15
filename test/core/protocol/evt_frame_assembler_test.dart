import 'dart:typed_data';

import 'package:aipin/core/protocol/evt_frame_assembler.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final codec = EvtProtocolCodec();

  test('assembles one complete frame', () {
    final frame = codec.encodeRequest(0x81, const [0x01, 0x02]);
    final result = EvtFrameAssembler().add(frame);

    expect(result.frames, hasLength(1));
    expect(result.frames.single, orderedEquals(frame));
    expect(result.rejectedFrames, isEmpty);
    expect(result.bufferedByteCount, 0);
  });

  test('holds a split frame until the final BLE value arrives', () {
    final frame = codec.encodeRequest(0x89, const [0x01]);
    final assembler = EvtFrameAssembler();

    final first = assembler.add(frame.sublist(0, 3));
    expect(first.frames, isEmpty);
    expect(first.bufferedByteCount, 3);

    final second = assembler.add(frame.sublist(3));
    expect(second.frames.single, orderedEquals(frame));
    expect(second.rejectedFrames, isEmpty);
    expect(second.bufferedByteCount, 0);
  });

  test('splits two coalesced frames and preserves order', () {
    final first = codec.encodeRequest(0x81, const [0x10]);
    final second = codec.encodeRequest(0x91, const [0x20, 0x30, 0x40]);
    final result = EvtFrameAssembler().add(<int>[...first, ...second]);

    expect(result.frames, hasLength(2));
    expect(result.frames[0], orderedEquals(first));
    expect(result.frames[1], orderedEquals(second));
  });

  test('drops noise and continues after a CRC-corrupted frame', () {
    final invalid = codec.encodeRequest(0x81, const [0x01]);
    invalid[invalid.length - 1] ^= 0xFF;
    final valid = codec.encodeRequest(0x89, const [0x01]);
    final result = EvtFrameAssembler().add(<int>[
      0x00,
      0x7F,
      ...invalid,
      ...valid,
    ]);

    expect(result.discardedByteCount, greaterThanOrEqualTo(2));
    expect(result.rejectedFrames, isNotEmpty);
    expect(result.frames.single, orderedEquals(valid));
  });

  test('resynchronizes when a corrupt length precedes a valid frame', () {
    // Declared length is intentionally larger than the available prefix.
    final corrupt = <int>[0xED, 0xFF, 0x7F, 0x01, 0xAA];
    final valid = codec.encodeRequest(0x81, const [0x02]);
    final result = EvtFrameAssembler().add(<int>[...corrupt, ...valid]);

    expect(result.frames.single, orderedEquals(valid));
    expect(result.discardedByteCount, greaterThan(0));
  });

  test('reset discards a partial frame from the previous connection', () {
    final frame = codec.encodeRequest(0x81, const [0x01]);
    final assembler = EvtFrameAssembler();
    assembler.add(frame.sublist(0, 4));
    assembler.reset();

    final result = assembler.add(frame.sublist(4));
    expect(result.frames, isEmpty);
    expect(result.bufferedByteCount, 0);
  });

  test('rejects values outside one-byte BLE range', () {
    expect(
      () => EvtFrameAssembler().add(<int>[256]),
      throwsA(isA<RangeError>()),
    );
  });

  test('returns independent frame copies', () {
    final frame = codec.encodeRequest(0x81, const [0x01]);
    final result = EvtFrameAssembler().add(Uint8List.fromList(frame));
    final emitted = result.frames.single;
    emitted[0] = 0;
    expect(frame.first, EvtFrameAssembler.head);
  });
}
