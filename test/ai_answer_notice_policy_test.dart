import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/ai_assistant/domain/entities/chat_message.dart';
import 'package:niswah/features/ai_assistant/domain/services/answer_notice_policy.dart';

/// TestFlight Feedback 2: the AI-generated / verify notes appear when the
/// server says so, but are not stacked under every short follow-up.
ChatMessage _m(
  String id,
  ChatRole role,
  String content, [
  Map<String, dynamic>? notice,
]) => ChatMessage(
  id: id,
  threadId: 't',
  userId: 'u',
  role: role,
  content: content,
  metadata: {'notice': ?notice},
  createdAt: DateTime(2026, 10, 31),
);

const _aiHealth = {'aiGenerated': true, 'verify': null, 'topic': 'health'};

void main() {
  test('a health answer without sources shows the AI-generated line', () {
    final messages = [
      _m('1', ChatRole.user, 'هل الجماع وقت الدورة له أضرار؟'),
      _m('2', ChatRole.assistant, 'جواب', _aiHealth),
    ];
    final lines = noticeLinesFor(messages, 1);
    expect(lines.aiGenerated, isTrue);
    expect(lines.verify, isNull);
  });

  test('a short follow-up on the same topic does not repeat it', () {
    final messages = [
      _m('1', ChatRole.user, 'ما علاج اللون الأحمر الغامق للدم؟'),
      _m('2', ChatRole.assistant, 'جواب', _aiHealth),
      _m('3', ChatRole.user, 'واللون البني؟'),
      _m('4', ChatRole.assistant, 'جواب', _aiHealth),
      _m('5', ChatRole.user, 'طيب وش أسوي؟'),
      _m('6', ChatRole.assistant, 'جواب', _aiHealth),
    ];
    expect(noticeLinesFor(messages, 3).aiGenerated, isFalse);
    expect(noticeLinesFor(messages, 5).aiGenerated, isFalse);
  });

  test('a new, longer question or a different topic shows it again', () {
    final messages = [
      _m('1', ChatRole.user, 'سؤال'),
      _m('2', ChatRole.assistant, 'جواب', _aiHealth),
      _m('3', ChatRole.user, 'هل يجوز الجماع وقت الحيض؟'),
      _m('4', ChatRole.assistant, 'جواب', {
        'aiGenerated': true,
        'topic': 'fiqh',
      }),
      _m(
        '5',
        ChatRole.user,
        'وإذا كانت الدورة متأخرة أكثر من أسبوعين وش ممكن يكون السبب يا دكتورة؟',
      ),
      _m('6', ChatRole.assistant, 'جواب', _aiHealth),
    ];
    expect(
      noticeLinesFor(messages, 3).aiGenerated,
      isTrue,
      reason: 'topic changed',
    );
    expect(
      noticeLinesFor(messages, 5).aiGenerated,
      isTrue,
      reason: 'not a short follow-up',
    );
  });

  test('the verify line is not repeated within two answers', () {
    final verify = {
      'aiGenerated': false,
      'verify': 'medical',
      'topic': 'health',
    };
    final messages = [
      _m('1', ChatRole.user, 'هل آخذ بروفين؟'),
      _m('2', ChatRole.assistant, 'جواب', verify),
      _m('3', ChatRole.user, 'وكم حبة؟'),
      _m('4', ChatRole.assistant, 'جواب', verify),
    ];
    expect(noticeLinesFor(messages, 1).verify, 'medical');
    expect(noticeLinesFor(messages, 3).verify, isNull);
  });

  test(
    'greetings, user messages and older replies without a notice show nothing',
    () {
      final messages = [
        _m('1', ChatRole.user, 'السلام عليكم'),
        _m('2', ChatRole.assistant, 'وعليكم السلام', {
          'aiGenerated': false,
          'topic': 'social',
        }),
        _m('3', ChatRole.assistant, 'رد قديم'),
      ];
      expect(noticeLinesFor(messages, 0).isEmpty, isTrue);
      expect(noticeLinesFor(messages, 1).isEmpty, isTrue);
      expect(noticeLinesFor(messages, 2).isEmpty, isTrue);
    },
  );

  test('a malformed notice is ignored', () {
    expect(AnswerNotice.fromJson('x'), isNull);
    expect(AnswerNotice.fromJson({'verify': 'legal'})!.verify, isNull);
  });
}
