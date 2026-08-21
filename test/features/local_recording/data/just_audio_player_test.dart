import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_audio_player.dart';

void main() {
  test('player stops previous audio before selecting a new file', () async {
    final player = FakeAudioPlayer();
    await player.play('/tmp/one.m4a');
    await player.play('/tmp/two.m4a');

    expect(player.playedPaths, ['/tmp/one.m4a', '/tmp/two.m4a']);
    expect(player.activePath, '/tmp/two.m4a');
  });
}
