import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/errors/network_failure.dart';
import '../../../../core/theme/app_theme.dart';

/// "Check your email" after an email sign-up (NJ-003..NJ-006, NJ-065,
/// NJ-066, NJ-296).
///
/// Niswah only knows that the email service accepted the request, never
/// that a message reached her inbox, so nothing here says it was
/// delivered. It names the destination, points to the Spam folder
/// («البريد غير المرغوب فيه (Spam)»), lets her correct a mistyped
/// address, and paces "Resend" with Auth's own wait instead of failing on
/// repeated taps.
class EmailConfirmationPending extends StatefulWidget {
  const EmailConfirmationPending({
    super.key,
    required this.email,
    required this.onResend,
    required this.onChangeEmail,
    required this.onBackToSignIn,
    this.cooldownSeconds = defaultCooldownSeconds,
  });

  /// Supabase Auth's default minimum interval between confirmation emails
  /// to one address. A shorter or longer project setting is still honored:
  /// a refusal carries Auth's own wait, which replaces this one.
  static const defaultCooldownSeconds = 60;

  final String email;

  /// Asks Auth to send another confirmation email. Throws
  /// [EmailRateLimitedFailure] when Auth refuses for now.
  final Future<void> Function() onResend;
  final VoidCallback onChangeEmail;
  final VoidCallback onBackToSignIn;
  final int cooldownSeconds;

  @override
  State<EmailConfirmationPending> createState() =>
      _EmailConfirmationPendingState();
}

class _EmailConfirmationPendingState extends State<EmailConfirmationPending> {
  Timer? _timer;
  int _secondsLeft = 0;
  bool _sending = false;
  String? _status;
  bool _statusIsError = false;

  bool get _arabic => AppLocaleController.instance.isArabic;
  String _t(String en, String ar) => _arabic ? ar : en;

  @override
  void initState() {
    super.initState();
    // The sign-up itself just requested the first email.
    _startCooldown(widget.cooldownSeconds);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _secondsLeft = seconds);
    if (seconds <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _secondsLeft -= 1);
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  Future<void> _resend() async {
    setState(() {
      _sending = true;
      _status = null;
    });
    try {
      await widget.onResend();
      if (!mounted) return;
      setState(() {
        _sending = false;
        _statusIsError = false;
        _status = _t(
          'We asked for another email to be sent to ${widget.email}. It can '
              'take a few minutes, and only the newest link may work.',
          'طلبنا إرسال رسالة أخرى إلى ${widget.email}. قد يستغرق وصولها بضع '
              'دقائق، وقد يعمل أحدث رابط فقط.',
        );
      });
      _startCooldown(widget.cooldownSeconds);
    } on EmailRateLimitedFailure catch (failure) {
      if (!mounted) return;
      final wait = failure.retryAfterSeconds ?? widget.cooldownSeconds;
      setState(() {
        _sending = false;
        _statusIsError = true;
        _status = _t(
          'Too many requests for now, so no new email was sent. You can ask '
              'again in $wait seconds.',
          'طلبات كثيرة الآن، لذلك لم تُرسل رسالة جديدة. يمكنكِ الطلب مجدداً '
              'بعد $wait ثانية.',
        );
      });
      _startCooldown(wait);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _statusIsError = true;
        _status = isNetworkFailure(error)
            ? _t(
                "Couldn't reach Niswah, so no email was requested. Check your "
                    'connection and try again.',
                'تعذّر الوصول إلى نسواه، لذلك لم يُطلب أي بريد. تحققي من '
                    'اتصالكِ ثم حاولي مجدداً.',
              )
            : _t(
                "Another email couldn't be requested right now. Try again in "
                    'a moment.',
                'تعذّر طلب رسالة أخرى الآن. حاولي مجدداً بعد قليل.',
              );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canResend = !_sending && _secondsLeft <= 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.mark_email_unread_outlined,
          size: 48,
          color: Color(0xFFE11D48),
        ),
        const SizedBox(height: 14),
        Text(
          _t('Check your email', 'تحققي من بريدكِ الإلكتروني'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          _t(
            'We asked for a confirmation link to be sent to:',
            'طلبنا إرسال رابط التأكيد إلى:',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
        ),
        const SizedBox(height: 4),
        // An address is always left-to-right, also inside Arabic text.
        Directionality(
          textDirection: TextDirection.ltr,
          child: SelectableText(
            widget.email,
            key: const Key('email_confirmation_destination'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _t(
            "Delivery can take a few minutes. Niswah can't see your inbox, so "
                "if it isn't there, check your Spam or Junk folder and other "
                'tabs such as Promotions.',
            'قد يستغرق وصول الرسالة بضع دقائق. لا يمكن لنسواه رؤية صندوق '
                'بريدكِ، فإن لم تجديها فتحققي من مجلد «البريد غير المرغوب فيه '
                '(Spam)» والتبويبات الأخرى مثل «العروض».',
          ),
          key: const Key('email_confirmation_spam_hint'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 8),
        Text(
          _t(
            'If this email already has a Niswah account, no new link is sent: '
                'sign in, or use "Forgot password?".',
            'إذا كان لهذا البريد حساب في نسواه فلن يُرسل رابط جديد: سجّلي '
                'الدخول أو استخدمي «نسيتِ كلمة المرور؟».',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
        ),
        if (_status != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              _status!,
              key: const Key('email_confirmation_status'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: _statusIsError
                    ? const Color(0xFFDC2626)
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        SizedBox(
          height: 54,
          child: FilledButton(
            key: const Key('email_confirmation_sign_in'),
            onPressed: _sending ? null : widget.onBackToSignIn,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE11D48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              _t("I've confirmed: sign in", 'أكّدتُ بريدي: تسجيل الدخول'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              key: const Key('email_confirmation_change_email'),
              onPressed: _sending ? null : widget.onChangeEmail,
              child: Text(_t('Wrong email? Change it', 'البريد خاطئ؟ غيّريه')),
            ),
            TextButton(
              key: const Key('email_confirmation_resend'),
              onPressed: canResend ? _resend : null,
              child: Text(
                _secondsLeft > 0
                    ? _t(
                        'Resend in $_secondsLeft s',
                        'إعادة الإرسال بعد $_secondsLeft ث',
                      )
                    : _t('Resend email', 'إعادة إرسال البريد'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
