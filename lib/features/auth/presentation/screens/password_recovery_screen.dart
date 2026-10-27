import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/auth/auth_controller.dart';
import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';

/// Displayed only after Supabase confirms a password recovery session.
class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key, this.updatePassword, this.onComplete});

  @visibleForTesting
  final Future<void> Function(String password)? updatePassword;
  @visibleForTesting
  final VoidCallback? onComplete;

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  String tr(String en, String ar) => AppLocaleController.instance.text(en, ar);

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final password = _password.text;
    if (password.length < 8) {
      setState(() => _error = tr('Use at least 8 characters.', 'استخدمي 8 أحرف على الأقل.'));
      return;
    }
    if (password != _confirm.text) {
      setState(() => _error = tr('Passwords do not match.', 'كلمتا المرور غير متطابقتين.'));
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      if (widget.updatePassword != null) {
        await widget.updatePassword!(password);
      } else {
        final client = NiswahSupabase.client;
        if (!AuthController.instance.passwordRecovery || client.auth.currentSession == null) {
          throw StateError('Recovery session unavailable');
        }
        await client.auth.updateUser(UserAttributes(password: password));
      }
      if (!mounted) return;
      if (widget.onComplete != null) {
        widget.onComplete!();
      } else {
        AuthController.instance.completePasswordRecovery();
      }
    } catch (_) {
      if (mounted) setState(() {
        _error = tr('Could not update your password. The link may have expired; request a new one and try again.', 'تعذّر تحديث كلمة المرور. قد يكون الرابط انتهت صلاحيته؛ اطلبي رابطًا جديدًا وحاولي مرة أخرى.');
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Reset password', 'إعادة تعيين كلمة المرور'))),
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('Choose a new password', 'اختاري كلمة مرور جديدة'), style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          TextField(key: const Key('new_password'), controller: _password, obscureText: true, autofillHints: const [AutofillHints.newPassword], decoration: InputDecoration(labelText: tr('New password', 'كلمة المرور الجديدة'))),
          const SizedBox(height: 14),
          TextField(key: const Key('confirm_password'), controller: _confirm, obscureText: true, decoration: InputDecoration(labelText: tr('Confirm password', 'تأكيد كلمة المرور'))),
          if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
          const SizedBox(height: 20),
          FilledButton(key: const Key('save_new_password'), onPressed: _saving ? null : _save, child: Text(_saving ? tr('Saving…', 'جارٍ الحفظ…') : tr('Save password', 'حفظ كلمة المرور'))),
        ],
      )),
    ))),
  );
}
