import '../entities/chat_message.dart';

/// What the server says about one answer (TestFlight Feedback 2,
/// 2026-10-31): whether it is AI-generated general information (a health or
/// fiqh answer with no supporting Niswah library source) and whether a
/// verification line fits. The server decides the facts; this app decides
/// only how often to repeat them, so a conversation stays readable.
class AnswerNotice {
  const AnswerNotice({required this.aiGenerated, this.verify, this.topic});

  /// "معلومة عامة مولّدة بالذكاء الاصطناعي، وقد تحتمل الخطأ."
  final bool aiGenerated;

  /// 'medical' or 'fiqh', or null.
  final String? verify;

  /// 'health', 'fiqh', 'social' or 'general', or null.
  final String? topic;

  bool get isEmpty => !aiGenerated && verify == null;

  /// Null for anything that is not a well-formed notice (an older server,
  /// or a message stored before this change).
  static AnswerNotice? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final verify = raw['verify'];
    final topic = raw['topic'];
    return AnswerNotice(
      aiGenerated: raw['aiGenerated'] == true,
      verify: verify == 'medical' || verify == 'fiqh' ? verify as String : null,
      topic: topic is String ? topic : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'aiGenerated': aiGenerated,
    'verify': verify,
    'topic': topic,
  };
}

/// The lines to show under the assistant message at [index].
class NoticeLines {
  const NoticeLines({required this.aiGenerated, this.verify});
  final bool aiGenerated;
  final String? verify;
  bool get isEmpty => !aiGenerated && verify == null;
  static const none = NoticeLines(aiGenerated: false);
}

/// A follow-up this short ("لماذا؟", "واللون البني؟", "طيب وش أسوي؟")
/// continues the previous answer rather than starting a new subject.
const shortFollowUpMaxWords = 6;

/// Repetition rules, so the same notice is not stacked under every short
/// follow-up:
/// * The AI-generated line is shown on a health or fiqh answer without a
///   library source, unless the previous answer already showed it for the
///   same topic and her message in between is a short follow-up.
/// * A verification line is shown when the server asked for it, unless one
///   of the previous two answers already showed the same one.
NoticeLines noticeLinesFor(List<ChatMessage> messages, int index) {
  final message = messages[index];
  if (message.role != ChatRole.assistant) return NoticeLines.none;
  final notice = AnswerNotice.fromJson(message.metadata['notice']);
  if (notice == null || notice.isEmpty) return NoticeLines.none;

  final previousAnswers = <AnswerNotice?>[];
  ChatMessage? userBetween;
  for (var i = index - 1; i >= 0 && previousAnswers.length < 2; i--) {
    final m = messages[i];
    if (m.role == ChatRole.user) {
      if (previousAnswers.isEmpty) userBetween ??= m;
    } else if (m.role == ChatRole.assistant) {
      previousAnswers.add(AnswerNotice.fromJson(m.metadata['notice']));
    }
  }

  var showAi = notice.aiGenerated;
  if (showAi && previousAnswers.isNotEmpty) {
    final last = previousAnswers.first;
    final shortFollowUp =
        userBetween != null &&
        userBetween.content.trim().split(RegExp(r'\s+')).length <=
            shortFollowUpMaxWords;
    if (last != null &&
        last.aiGenerated &&
        last.topic == notice.topic &&
        shortFollowUp) {
      showAi = false;
    }
  }

  var verify = notice.verify;
  if (verify != null &&
      previousAnswers.any((previous) => previous?.verify == verify)) {
    verify = null;
  }
  return NoticeLines(aiGenerated: showAi, verify: verify);
}
