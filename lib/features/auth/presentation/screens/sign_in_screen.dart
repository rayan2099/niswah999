import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../core/auth/auth_controller.dart';
import '../../../../core/data/countries.dart';
import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/niswah_logo.dart';
import '../../../legal/presentation/screens/privacy_policy_screen.dart';
import '../../data/repositories/auth_repository_impl.dart';

String _tr(String english, String arabic) =>
    AppLocaleController.instance.text(english, arabic);

/// Shown by the root router in main.dart whenever no Supabase session
/// exists, and reused as onboarding's own login step. On successful auth
/// this does not navigate anywhere itself by default — [onAuthenticated]
/// decides what happens next (the root router just lets Supabase's
/// auth-state stream and `AuthController` swap it to `NiswahHomeShell`
/// reactively; onboarding advances to its next step instead).
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.onAuthenticated, this.embedded = false});

  /// Called after a successful sign-in or sign-up. Defaults to a no-op —
  /// the root router's `AuthController` listener handles routing once the
  /// session lands, matching how this screen has always worked as the
  /// unauthenticated entry point.
  final VoidCallback? onAuthenticated;

  /// True when this screen is reused as onboarding's own login step
  /// (step 3), rather than shown as the app's top-level unauthenticated
  /// route. In that context this screen cannot own a `Scaffold` or a
  /// `Stack`/`Positioned` layout — both require bounded height from their
  /// parent, and onboarding's shared step shell intentionally hands its
  /// switched content unbounded height (the same mechanism every other,
  /// plain-Column step already relies on to stay scroll-safe). Flutter
  /// throws "RenderAnimatedOpacity object was given an infinite size
  /// during layout" the moment this screen is switched into under that
  /// shell otherwise (RR-009). Defaults to `false` — the standalone,
  /// top-level usage in `main.dart` is unaffected.
  final bool embedded;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  void _onAuthenticated() => widget.onAuthenticated?.call();

  /// PC-001: the consent checkbox previously gated nothing — every entry
  /// path (email, phone, Google) called straight into Supabase auth
  /// regardless of its state. It sits above all three entry points in the
  /// UI, so it gates all three here, uniformly, matching that layout's own
  /// intent — not just the email/phone sheet. Lifted up from
  /// `_SignInContent` (which only renders the checkbox) so this state,
  /// where the actual auth calls happen, can see and enforce it.
  bool _agreed = false;

  Future<void> _requireConsent(Future<void> Function() proceed) async {
    if (!_agreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'Please agree to the Privacy Policy and Terms of Use first.',
              'يُرجى الموافقة على سياسة الخصوصية وشروط الاستخدام أولاً.',
            ),
          ),
        ),
      );
      return;
    }
    await proceed();
  }

  Future<void> _showAuthSheet({required bool isPhone}) => _requireConsent(
    () async {
      final success = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        builder: (_) => _AuthSheet(isPhone: isPhone),
      );

      if (success == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_tr('Welcome back!', 'أهلاً بعودتكِ!'))),
        );
        _onAuthenticated();
      }
    },
  );

  Future<void> _signInWithGoogle() => _requireConsent(_signInWithGoogleImpl);

  Future<void> _signInWithGoogleImpl() async {
    try {
      final repo = AuthRepositoryImpl();
      await repo.signInWithGoogle();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr('Signed in with Google', 'تم تسجيل الدخول عبر جوجل'),
            ),
          ),
        );
        _onAuthenticated();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: _SignInContent(
        onEmail: () => _showAuthSheet(isPhone: false),
        onPhone: () => _showAuthSheet(isPhone: true),
        onGoogle: _signInWithGoogle,
        agreed: _agreed,
        onAgreedChanged: (value) => setState(() => _agreed = value),
      ),
    );

    if (widget.embedded) {
      // See the `embedded` doc comment above — no Scaffold, no
      // Stack/Positioned. A plain Column sizes to its own content
      // regardless of whether its parent's height is bounded or
      // unbounded, so it is safe under onboarding's shared step shell.
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Align(
            alignment: AlignmentDirectional.topEnd,
            child: Padding(
              padding: EdgeInsetsDirectional.only(end: 8, top: 8),
              child: _LanguageToggle(),
            ),
          ),
          content,
        ],
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            Center(child: content),
            const PositionedDirectional(
              top: 8,
              end: 8,
              child: _LanguageToggle(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact EN/AR switch shown on the sign-in screen — the earliest point a
/// new user reaches, before any account-level language preference exists.
class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle();

  @override
  Widget build(BuildContext context) {
    final isArabic = AppLocaleController.instance.isArabic;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0xFFFCE7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            label: 'EN',
            selected: !isArabic,
            onTap: () => AppLocaleController.instance.setArabic(false),
          ),
          _segment(
            label: 'ع',
            selected: isArabic,
            onTap: () => AppLocaleController.instance.setArabic(true),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFE11D48) : Colors.transparent,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : AppColors.textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _SignInContent extends StatelessWidget {
  const _SignInContent({
    required this.onPhone,
    required this.onEmail,
    required this.onGoogle,
    required this.agreed,
    required this.onAgreedChanged,
  });
  final VoidCallback onPhone;
  final VoidCallback onEmail;
  final VoidCallback onGoogle;
  final bool agreed;
  final ValueChanged<bool> onAgreedChanged;

  void _openPrivacyPolicy(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const PrivacyPolicyScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // Logo
      const Center(child: NiswahLogo(size: 96)),
      const SizedBox(height: 28),
      // Title & subtitle
      Text(
        _tr(
          'Understand your cycle, with peace of mind',
          'افهمي دورتكِ واطمنّي',
        ),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.displayMedium?.copyWith(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF9F1239),
          fontFamily: AppTypography.serifFamily,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        _tr(
          'Predictions for Haid and Taharah with Fiqh and health guidance — and privacy that stays yours alone.',
          'تنبؤ للحيض والطهارة والعمل مع إرشاد فقهي وصحي، وخصوصية تبقى لكِ وحدها.',
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          height: 1.6,
        ),
      ),
      const SizedBox(height: 30),
      // Feature grid
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .6),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: const Color(0xFFFCE7EB)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _FeatureTile(
                    icon: Icons.calendar_month_rounded,
                    iconColor: const Color(0xFFEF4444),
                    label: _tr('Cycle prediction', 'تتبع الدورة'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FeatureTile(
                    icon: Icons.favorite_rounded,
                    iconColor: const Color(0xFFF59E0B),
                    label: _tr('Purity planning', 'تخطيط للحمل'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _FeatureTile(
                    icon: Icons.child_care_rounded,
                    iconColor: const Color(0xFF10B981),
                    label: _tr('Pregnancy prediction', 'تتبع الحمل'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FeatureTile(
                    icon: Icons.medical_services_outlined,
                    iconColor: const Color(0xFF3B82F6),
                    label: _tr('Smart doctor', 'طبيبة ذكية'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _FeatureTile(
                    icon: Icons.groups_rounded,
                    iconColor: const Color(0xFFA855F7),
                    label: _tr('Women community', 'مجتمع نسائي'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FeatureTile(
                    icon: Icons.description_outlined,
                    iconColor: const Color(0xFF64748B),
                    label: _tr('PDF reports', 'تقارير PDF'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _FeatureTile(
                    icon: Icons.nights_stay_rounded,
                    iconColor: const Color(0xFF14B8A6),
                    label: _tr('Dream interpretation', 'تفسير الأحلام'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FeatureTile(
                    icon: Icons.auto_awesome_rounded,
                    iconColor: const Color(0xFFEC4899),
                    label: _tr('Daily insights', 'روؤى يومية'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 36),
      // Privacy checkbox — gates all three entry points below (PC-001).
      InkWell(
        key: const Key('consent_checkbox'),
        onTap: () => onAgreedChanged(!agreed),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              // This is a hand-drawn checkbox, not a Material `Checkbox` —
              // without an explicit Semantics wrapper it would expose no
              // checked state at all to a screen reader (confirmed: no
              // Semantics anywhere in this InkWell before this fix). `onTap`
              // here gives the node its own activatable action, independent
              // of (but calling the same callback as) the enclosing
              // InkWell's tap handling for sighted users.
              Semantics(
                checked: agreed,
                label: _tr(
                  'Agree to the Privacy Policy and Terms of Use',
                  'الموافقة على سياسة الخصوصية وشروط الاستخدام',
                ),
                onTap: () => onAgreedChanged(!agreed),
                child: ExcludeSemantics(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: agreed ? const Color(0xFFE11D48) : Colors.white,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: agreed
                            ? const Color(0xFFE11D48)
                            : const Color(0xFFCBD5E1),
                        width: 1.5,
                      ),
                    ),
                    child: agreed
                        ? const Icon(
                            Icons.check_rounded,
                            size: 13,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    text: _tr('I agree to the ', 'أوافق على '),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                    children: [
                      TextSpan(
                        text: _tr('Privacy Policy', 'سياسة الخصوصية'),
                        style: const TextStyle(
                          color: Color(0xFFE11D48),
                          fontWeight: FontWeight.w700,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => _openPrivacyPolicy(context),
                      ),
                      TextSpan(text: _tr(' and ', ' و ')),
                      TextSpan(
                        text: _tr('Terms of Use', 'شروط الاستخدام'),
                        style: const TextStyle(
                          color: Color(0xFFE11D48),
                          fontWeight: FontWeight.w700,
                        ),
                        // Terms of Use content isn't a distinct document
                        // yet — points to the same policy screen rather
                        // than being a dead/unresponsive link.
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => _openPrivacyPolicy(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      // Email + Phone buttons side by side
      Row(
        children: [
          Expanded(
            child: _AuthChoiceButton(
              label: _tr('Email', 'البريد الإلكتروني'),
              onTap: onEmail,
              background: const Color(0xFFFDF2F4),
              foreground: const Color(0xFFBE123C),
              icon: null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _AuthChoiceButton(
              label: _tr('Mobile', 'الجوال'),
              onTap: onPhone,
              background: const Color(0xFFECFDF5),
              foreground: const Color(0xFF059669),
              icon: Icons.phone_outlined,
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      // "or" divider
      Row(
        children: [
          const Expanded(child: Divider(color: Color(0xFFE5E7EB))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _tr('or', 'أو'),
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ),
          const Expanded(child: Divider(color: Color(0xFFE5E7EB))),
        ],
      ),
      const SizedBox(height: 18),
      // Google button
      SizedBox(
        height: 54,
        child: OutlinedButton.icon(
          onPressed: onGoogle,
          icon: const Icon(
            Icons.g_mobiledata_rounded,
            size: 26,
            color: Color(0xFF4285F4),
          ),
          label: Text(
            _tr('Continue with Google', 'المتابعة مع Google'),
            style: const TextStyle(
              color: Color(0xFF374151),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFE5E7EB)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    ],
  );
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.iconColor,
    required this.label,
  });
  final IconData icon;
  final Color iconColor;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 13),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFF3F4F6)),
    ),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 15),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF374151),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _AuthChoiceButton extends StatelessWidget {
  const _AuthChoiceButton({
    required this.label,
    required this.onTap,
    required this.background,
    required this.foreground,
    required this.icon,
  });
  final String label;
  final VoidCallback onTap;
  final Color background;
  final Color foreground;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
    child: OutlinedButton.icon(
      onPressed: onTap,
      icon: icon != null
          ? Icon(icon, size: 19, color: foreground)
          : const SizedBox.shrink(),
      label: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: background,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

class _AuthSheet extends StatefulWidget {
  const _AuthSheet({required this.isPhone});
  final bool isPhone;
  @override
  State<_AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<_AuthSheet> {
  bool _isSignUp = false;
  bool _obscure = true;
  bool _loading = false;
  String? _error;
  late Country _country;

  // Set once a phone sign-up succeeds but still needs its SMS code
  // confirmed — required whenever the Supabase project has "Enable phone
  // confirmations" on, since signUpWithPhone alone leaves the account
  // unconfirmed with no active session.
  bool _awaitingPhoneOtp = false;
  String? _pendingPhone;

  // Set once an email sign-up succeeds but still needs its confirmation
  // link clicked — required whenever the Supabase project has "Confirm
  // email" on, since signUpWithEmail alone leaves the account unconfirmed
  // with no active session.
  bool _awaitingEmailConfirmation = false;
  String? _pendingEmail;

  final _nameController = TextEditingController();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _country = kCountries.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _identifierController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = AuthRepositoryImpl();
      if (widget.isPhone) {
        final fullPhone =
            '${_country.dial}${_identifierController.text.trim()}';
        if (_isSignUp) {
          await repo.signUpWithPhone(
            phone: fullPhone,
            password: _passwordController.text,
            displayName: _nameController.text.trim(),
          );
          if (mounted) {
            setState(() {
              _pendingPhone = fullPhone;
              _awaitingPhoneOtp = true;
              _loading = false;
            });
          }
          return;
        } else {
          await repo.signInWithPhone(
            phone: fullPhone,
            password: _passwordController.text,
          );
        }
      } else {
        if (_isSignUp) {
          final email = _identifierController.text.trim();
          final needsConfirmation = await repo.signUpWithEmail(
            email: email,
            password: _passwordController.text,
            displayName: _nameController.text.trim(),
          );
          if (needsConfirmation) {
            if (mounted) {
              setState(() {
                _pendingEmail = email;
                _awaitingEmailConfirmation = true;
                _loading = false;
              });
            }
            return;
          }
        } else {
          await repo.signInWithEmail(
            email: _identifierController.text.trim(),
            password: _passwordController.text,
          );
        }
      }
      if (mounted) {
        if (_isSignUp) AuthController.instance.markSignedUp();
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _verifyOtp() async {
    final phone = _pendingPhone;
    if (phone == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = AuthRepositoryImpl();
      await repo.verifyPhoneOtp(phone: phone, token: _otpController.text);
      if (mounted) {
        if (_isSignUp) AuthController.instance.markSignedUp();
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _resendOtp() async {
    final phone = _pendingPhone;
    if (phone == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = AuthRepositoryImpl();
      await repo.resendPhoneOtp(phone: phone);
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_tr('Code resent.', 'تم إعادة إرسال الرمز.'))),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _resendEmailConfirmation() async {
    final email = _pendingEmail;
    if (email == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = AuthRepositoryImpl();
      await repo.resendEmailConfirmation(email: email);
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_tr('Email resent.', 'تم إعادة إرسال البريد.')),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      16,
      24,
      MediaQuery.viewInsetsOf(context).bottom + 28,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 22),
          if (_awaitingPhoneOtp)
            ..._otpStepChildren()
          else if (_awaitingEmailConfirmation)
            ..._emailConfirmationStepChildren()
          else
            ..._credentialsStepChildren(),
        ],
      ),
    ),
  );

  List<Widget> _otpStepChildren() => [
    Text(
      _tr('Enter confirmation code', 'أدخلي رمز التأكيد'),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 8),
    Text(
      _tr(
        'We sent a code to ${_pendingPhone ?? ''}',
        'أرسلنا رمزاً إلى ${_pendingPhone ?? ''}',
      ),
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
    ),
    const SizedBox(height: 22),
    TextField(
      controller: _otpController,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: 6,
      style: const TextStyle(fontSize: 22, letterSpacing: 8),
      decoration: InputDecoration(
        counterText: '',
        hintText: '••••••',
        labelText: _tr('Confirmation code', 'رمز التأكيد'),
      ),
    ),
    if (_error != null) ...[
      const SizedBox(height: 12),
      Text(
        _error!,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
      ),
    ],
    const SizedBox(height: 22),
    SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: _loading ? null : _verifyOtp,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFE11D48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                  semanticsLabel: _tr('Loading', 'جارٍ التحميل'),
                ),
              )
            : Text(
                _tr('Verify', 'تأكيد'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
      ),
    ),
    const SizedBox(height: 14),
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: _loading
              ? null
              : () => setState(() {
                  _awaitingPhoneOtp = false;
                  _pendingPhone = null;
                  _otpController.clear();
                }),
          child: Text(_tr('Change phone number', 'تغيير رقم الهاتف')),
        ),
        TextButton(
          onPressed: _loading ? null : _resendOtp,
          child: Text(_tr('Resend code', 'إعادة إرسال الرمز')),
        ),
      ],
    ),
  ];

  List<Widget> _emailConfirmationStepChildren() => [
    const Icon(
      Icons.mark_email_unread_outlined,
      size: 48,
      color: Color(0xFFE11D48),
    ),
    const SizedBox(height: 14),
    Text(
      _tr('Check your email', 'تحققي من بريدكِ الإلكتروني'),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 8),
    Text(
      _tr(
        'We sent a confirmation link to ${_pendingEmail ?? ''}. '
        'Click it, then come back and sign in.',
        'أرسلنا رابط تأكيد إلى ${_pendingEmail ?? ''}. '
        'اضغطي عليه ثم عودي لتسجيل الدخول.',
      ),
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
    ),
    if (_error != null) ...[
      const SizedBox(height: 12),
      Text(
        _error!,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
      ),
    ],
    const SizedBox(height: 22),
    SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: _loading
            ? null
            : () => setState(() {
                _awaitingEmailConfirmation = false;
                _pendingEmail = null;
                _isSignUp = false;
              }),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFE11D48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          _tr('Back to Sign In', 'العودة لتسجيل الدخول'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ),
    const SizedBox(height: 14),
    Center(
      child: TextButton(
        onPressed: _loading ? null : _resendEmailConfirmation,
        child: _loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  semanticsLabel: _tr('Loading', 'جارٍ التحميل'),
                ),
              )
            : Text(_tr('Resend email', 'إعادة إرسال البريد')),
      ),
    ),
  ];

  List<Widget> _credentialsStepChildren() => [
    // Sign In / Sign Up toggle
    Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(child: _modeTab(false)),
          Expanded(child: _modeTab(true)),
        ],
      ),
    ),
    const SizedBox(height: 22),
    if (_isSignUp) ...[
      TextField(
        controller: _nameController,
        decoration: InputDecoration(
          labelText: _tr('Full name', 'الاسم الكامل'),
          prefixIcon: const Icon(Icons.person_outline_rounded),
        ),
      ),
      const SizedBox(height: 14),
    ],
    if (widget.isPhone)
      // Force LTR so the code prefix stays on the left and the
      // number field on the right in both languages.
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Country code picker
            Container(
              width: 118,
              height: 56,
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: DropdownButtonHideUnderline(
                child: ButtonTheme(
                  alignedDropdown: true,
                  child: DropdownButton<Country>(
                    value: _country,
                    isExpanded: true,
                    icon: const Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    items: kCountries
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: '${c.flag} '),
                                  TextSpan(
                                    text: c.dial,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    selectedItemBuilder: (_) => kCountries
                        .map(
                          (c) => Center(
                            child: Text(
                              '${c.flag} ${c.dial}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (c) => setState(() => _country = c ?? _country),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _identifierController,
                keyboardType: TextInputType.phone,
                textAlign: TextAlign.left,
                decoration: InputDecoration(
                  labelText: _tr('Phone number', 'رقم الهاتف'),
                  hintText: '5X XXX XXXX',
                ),
              ),
            ),
          ],
        ),
      )
    else
      TextField(
        controller: _identifierController,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
          labelText: _tr('Email', 'البريد الإلكتروني'),
          prefixIcon: const Icon(Icons.email_outlined),
        ),
      ),
    const SizedBox(height: 14),
    TextField(
      controller: _passwordController,
      obscureText: _obscure,
      decoration: InputDecoration(
        labelText: _tr('Password', 'كلمة المرور'),
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          icon: Icon(
            _obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 20,
          ),
          tooltip: _obscure
              ? _tr('Show password', 'إظهار كلمة المرور')
              : _tr('Hide password', 'إخفاء كلمة المرور'),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    ),
    if (_error != null) ...[
      const SizedBox(height: 12),
      Text(
        _error!,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
      ),
    ],
    const SizedBox(height: 22),
    SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: _loading ? null : _submit,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFE11D48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                  semanticsLabel: _tr('Loading', 'جارٍ التحميل'),
                ),
              )
            : Text(
                _isSignUp
                    ? _tr('Create Account', 'إنشاء حساب')
                    : _tr('Sign In', 'تسجيل الدخول'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
      ),
    ),
  ];

  Widget _modeTab(bool signUp) {
    final active = _isSignUp == signUp;
    return GestureDetector(
      onTap: () => setState(() => _isSignUp = signUp),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          signUp
              ? _tr('Sign Up', 'إنشاء حساب')
              : _tr('Sign In', 'تسجيل الدخول'),
          style: TextStyle(
            color: active ? const Color(0xFFBE123C) : AppColors.textTertiary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
