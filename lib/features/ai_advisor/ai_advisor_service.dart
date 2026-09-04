import '../../core/errors/app_error_reporter.dart';
import '../../core/network/supabase_client.dart';
import '../cycle_tracking/domain/services/madhhab_rule_evaluator.dart';

class FiqhCitation {
  const FiqhCitation({
    required this.url,
    required this.title,
    required this.startIndex,
    required this.endIndex,
  });

  factory FiqhCitation.fromJson(Map<String, dynamic> json) => FiqhCitation(
    url: json['url']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    startIndex: (json['startIndex'] as num?)?.toInt() ?? 0,
    endIndex: (json['endIndex'] as num?)?.toInt() ?? 0,
  );

  final String url;
  final String title;
  final int startIndex;
  final int endIndex;

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'start_index': startIndex,
    'end_index': endIndex,
  };
}

class FiqhAnswer {
  const FiqhAnswer({required this.text, this.citations = const []});

  final String text;
  final List<FiqhCitation> citations;
}

/// Calls the `fiqh-advisor-chat` Supabase Edge Function, which owns the
/// system prompt, the Gemini call, and the trusted-citation filter
/// server-side (moved off the client per the Gemini trust-boundary
/// remediation — closes SEC-001/AB-002/AB-012 for this feature).
class AiAdvisorService {
  const AiAdvisorService._();

  static const instance = AiAdvisorService._();

  static const _noSourcesFallbackAr =
      'تعذر الوصول إلى المصادر الموثقة الآن. لا يمكن إصدار توجيه فقهي آلي دون مصادر؛ يُرجى المحاولة لاحقاً أو سؤال عالِمة أو جهة إفتاء مؤهلة.';

  Future<FiqhAnswer> askFiqh({
    required String question,
    required Madhhab madhhab,
  }) async {
    final client = NiswahSupabase.clientOrNull;
    if (client == null) {
      return const FiqhAnswer(text: _noSourcesFallbackAr);
    }

    try {
      final response = await client.functions.invoke(
        'fiqh-advisor-chat',
        body: {'question': question, 'madhhab': madhhab.name},
      );

      final data = response.data;
      if (data is! Map || response.status != 200) {
        final error = data is Map ? data['error']?.toString() : null;
        throw StateError(
          error ?? 'Fiqh advisor service failed (${response.status}).',
        );
      }

      final citations = (data['citations'] as List<dynamic>? ?? [])
          .map((item) => FiqhCitation.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      return FiqhAnswer(
        text: data['text']?.toString() ?? _noSourcesFallbackAr,
        citations: citations,
      );
    } catch (error, stack) {
      AppErrorReporter.report(error, stack, context: 'AiAdvisorService.askFiqh');
      return const FiqhAnswer(text: _noSourcesFallbackAr);
    }
  }
}
