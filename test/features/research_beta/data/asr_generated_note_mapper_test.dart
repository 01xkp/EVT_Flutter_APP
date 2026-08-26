import 'package:aipin/features/research_beta/data/asr_generated_note_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('renders the verified structured note content as Markdown', () {
    final result = mapAsrGeneratedNote(<String, Object?>{
      'content': <String, Object?>{
        'overview': <Object?>[
          <String, Object?>{
            'entry_id': 'internal-id',
            'title': '项目回顾',
            'text': '确定上线时间。',
            'evidence': <String, Object?>{
              'text': '原始依据文本。',
              'time_state': 'no_time_evidence',
            },
          },
        ],
        'decisions': <Object?>['明日发布'],
        'tasks': const <Object?>[],
        'pending_confirmation': const <Object?>[],
        'knowledge_blocks': const <Object?>[],
      },
    });

    expect(result, isNotNull);
    expect(result!.title, 'AI 总结');
    expect(result.summary, '确定上线时间。');
    expect(result.summary, isNot(contains('##')));
    expect(result.summary, isNot(contains('项目回顾')));
    expect(result.summary, isNot(contains('entry_id')));
    expect(result.summary, isNot(contains('time_state')));
    expect(result.summary, isNot(contains('原始依据文本。')));
    expect(result.summary, isNot(contains('明日发布')));
  });
}
