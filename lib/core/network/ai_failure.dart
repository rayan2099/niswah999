import '../localization/app_locale_controller.dart';

/// Why an AI chat request failed, as the app shows it.
///
/// Testing feedback 2026-10-30: every failure used to surface as the same
/// "تعذر إرسال الرسالة" line, so a timeout, a busy provider and an expired
/// session were indistinguishable for the person and for support. The Edge
/// Functions now send a `category` (supabase/functions/_shared/
/// chat_contract.ts); this maps it, plus the failures that never reach the
/// server (offline, client timeout), to one message each.
enum AiFailureCategory {
  offline,
  timeout,
  authExpired,
  rateLimited,
  providerBusy,
  providerUnavailable,
  serviceMisconfigured,
  malformedResponse,
  invalidRequest,
  accountChanged,
  internal;

  static AiFailureCategory fromServer(String? value, int status) {
    switch (value) {
      case 'auth_expired':
        return authExpired;
      case 'rate_limited':
        return rateLimited;
      case 'timeout':
        return timeout;
      case 'provider_busy':
        return providerBusy;
      case 'provider_unavailable':
      case 'limiter_unavailable':
        return providerUnavailable;
      case 'service_misconfigured':
        return serviceMisconfigured;
      case 'malformed_response':
        return malformedResponse;
      case 'invalid_request':
        return invalidRequest;
      case 'internal_error':
        return internal;
    }
    // A function deployed before categories existed, or the platform
    // gateway itself (for example an expired JWT rejected before the
    // function runs), only gives a status.
    if (status == 401) return authExpired;
    if (status == 429) return rateLimited;
    if (status == 504) return timeout;
    if (status == 503) return providerUnavailable;
    if (status == 400 || status == 413) return invalidRequest;
    if (status == 502) return providerUnavailable;
    return internal;
  }
}

class AiFailure implements Exception {
  const AiFailure(
    this.category, {
    this.correlationId,
    this.retryAfter,
    this.status,
  });

  final AiFailureCategory category;

  /// The id the app sent as `x-niswah-request-id`, echoed in the server's
  /// logs. Shown shortened so support can find the failure without the
  /// person describing their conversation.
  final String? correlationId;
  final Duration? retryAfter;
  final int? status;

  /// Whether sending the same message again can help.
  bool get retryable => switch (category) {
    AiFailureCategory.invalidRequest ||
    AiFailureCategory.serviceMisconfigured ||
    AiFailureCategory.accountChanged => false,
    _ => true,
  };

  String get shortReference {
    final id = correlationId;
    if (id == null || id.length < 8) return '';
    return id.substring(0, 8);
  }

  String get message {
    final t = AppLocaleController.instance.text;
    final wait = retryAfter;
    return switch (category) {
      AiFailureCategory.offline => t(
        'No internet connection. Your message is kept; send it again when you are online.',
        'لا يوجد اتصال بالإنترنت. رسالتكِ محفوظة؛ أعيدي إرسالها عند عودة الاتصال.',
      ),
      AiFailureCategory.timeout => t(
        'The reply took too long. Try again.',
        'استغرق الرد وقتًا أطول من المعتاد. حاولي مرة أخرى.',
      ),
      AiFailureCategory.authExpired => t(
        'Your session ended. Sign in again, then resend your message.',
        'انتهت جلستكِ. سجّلي الدخول مرة أخرى ثم أعيدي إرسال رسالتكِ.',
      ),
      AiFailureCategory.rateLimited =>
        wait != null && wait.inSeconds > 0
            ? t(
                'You have sent many messages in a short time. Try again in ${_humanWait(wait, false)}.',
                'أرسلتِ رسائل كثيرة خلال وقت قصير. حاولي بعد ${_humanWait(wait, true)}.',
              )
            : t(
                'You have sent many messages in a short time. Try again shortly.',
                'أرسلتِ رسائل كثيرة خلال وقت قصير. حاولي بعد قليل.',
              ),
      AiFailureCategory.providerBusy => t(
        'The assistant is busy right now. Try again in a moment.',
        'المساعدة مشغولة الآن. حاولي بعد لحظات.',
      ),
      AiFailureCategory.providerUnavailable => t(
        'The assistant is temporarily unavailable. Try again shortly.',
        'المساعدة غير متاحة مؤقتًا. حاولي بعد قليل.',
      ),
      AiFailureCategory.serviceMisconfigured => t(
        'The assistant is unavailable right now. We have been notified.',
        'المساعدة غير متاحة حاليًا، وقد سُجّل الخلل لفريق نسوة.',
      ),
      AiFailureCategory.malformedResponse => t(
        'The reply could not be read. Try again.',
        'تعذّرت قراءة الرد. حاولي مرة أخرى.',
      ),
      AiFailureCategory.invalidRequest => t(
        'This message could not be sent. Try shortening it.',
        'تعذّر إرسال هذه الرسالة. جرّبي اختصارها.',
      ),
      AiFailureCategory.accountChanged => t(
        'The account changed before the reply arrived.',
        'تغيّر الحساب قبل وصول الرد.',
      ),
      AiFailureCategory.internal => t(
        'Something went wrong. Try again.',
        'حدث خطأ غير متوقع. حاولي مرة أخرى.',
      ),
    };
  }

  static String _humanWait(Duration wait, bool arabic) {
    final minutes = (wait.inSeconds / 60).ceil();
    if (wait.inSeconds < 60) {
      return arabic ? '${wait.inSeconds} ثانية' : '${wait.inSeconds} seconds';
    }
    return arabic ? '$minutes دقيقة' : '$minutes minutes';
  }

  @override
  String toString() =>
      'AiFailure(${category.name}, status: $status, ref: $shortReference)';
}
