import 'package:aipin/core/documents/document_file_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses a normalized custom name with exactly one extension', () {
    expect(
      DocumentFileName.build(
        customBaseName: '  会议:纪要.md ',
        fallbackTime: DateTime(2026, 8, 25),
        fallbackSuffix: '总结',
        extension: 'md',
      ),
      '会议纪要.md',
    );
  });

  test('removes path and reserved filename characters', () {
    expect(
      DocumentFileName.normalizeCustomBaseName(' \\访谈/第:一*次?"<>|.txt '),
      '访谈第一次',
    );
  });

  test('falls back to a timestamp name when no usable custom name exists', () {
    expect(
      DocumentFileName.build(
        customBaseName: ' \\ / : * ? " < > | ',
        fallbackTime: DateTime(2026, 8, 25),
        fallbackSuffix: '转写',
        extension: '.txt',
      ),
      '20260825_000000_转写.txt',
    );
  });

  test('rejects reserved device names and dot-only names', () {
    expect(DocumentFileName.normalizeCustomBaseName('CON'), isNull);
    expect(DocumentFileName.normalizeCustomBaseName('lpt9.txt'), isNull);
    expect(DocumentFileName.normalizeCustomBaseName(' . '), isNull);
  });

  test('removes controls and trailing path-unsafe suffixes', () {
    expect(DocumentFileName.normalizeCustomBaseName('  访谈\u0000记录.  '), '访谈记录');
  });
}
