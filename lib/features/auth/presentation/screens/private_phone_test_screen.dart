import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';

/// UI visibility only; the RPC independently enforces staging + tester access.
const privatePhoneTestBuild = bool.fromEnvironment('PRIVATE_PHONE_TESTING');
String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

class PrivatePhoneTestScreen extends StatefulWidget {
  const PrivatePhoneTestScreen({super.key});
  @override
  State<PrivatePhoneTestScreen> createState() => _PrivatePhoneTestScreenState();
}

class _PrivatePhoneTestScreenState extends State<PrivatePhoneTestScreen> {
  final _phone = TextEditingController(text: '+966');
  final _code = TextEditingController();
  String? _testCode;
  String? _message;
  bool _busy = false;
  bool _done = false;
  bool _sessionChanged = false;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    final client = NiswahSupabase.client;
    final owner = client.auth.currentUser?.id;
    _authSubscription = client.auth.onAuthStateChange.listen((state) {
      if (state.session?.user.id != owner ||
          state.event == AuthChangeEvent.signedOut) {
        _sessionChanged = true;
        _testCode = null;
        _code.clear();
        if (mounted) Navigator.of(context).pop();
      }
    });
  }

  Future<void> _request({required bool complete}) async {
    if (_busy || _sessionChanged || !privatePhoneTestBuild) return;
    final client = NiswahSupabase.client;
    final owner = client.auth.currentUser?.id;
    if (owner == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = Map<String, dynamic>.from(
        await client.rpc(
          complete ? 'complete_private_phone_test' : 'start_private_phone_test',
          params: complete
              ? {'p_code': _code.text.trim()}
              : {'p_phone': _phone.text.replaceAll(RegExp(r'[\s()-]'), '')},
        ) as Map,
      );
      if (!mounted) return;
      if (_sessionChanged || client.auth.currentUser?.id != owner) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        final error = result['error'];
        _message = switch (error) {
          'not_allowed' => _t(
            'Available only to approved staging testers with verified email.',
            'متاح فقط لمختبرات البيئة التجريبية المعتمدات ببريد موثّق.',
          ),
          'invalid_phone' => _t(
            'Enter an international number, for example +9665XXXXXXXX.',
            'أدخلي الرقم بالصيغة الدولية، مثل +9665XXXXXXXX.',
          ),
          'cooldown' => _t(
            'Wait 60 seconds between code requests.',
            'انتظري 60 ثانية بين طلبات الرمز.',
          ),
          'invalid_code' => _t(
            'Incorrect test code.',
            'رمز الاختبار غير صحيح.',
          ),
          'expired' => _t(
            'Request a new code. This code expired or reached its attempt limit.',
            'اطلبي رمزاً جديداً؛ انتهت صلاحية الرمز أو عدد محاولاته.',
          ),
          null => null,
          _ => _t(
            'Unable to continue. Try again.',
            'تعذّر المتابعة. حاولي مجدداً.',
          ),
        };
        if (error == null && !complete) {
          _testCode = result['test_code'] as String;
          _code.clear();
        }
        if (error == null && complete && result['completed'] == true) {
          _done = true;
          _testCode = null;
          _code.clear();
        }
      });
    } catch (_) {
      if (mounted && client.auth.currentUser?.id == owner) {
        setState(
          () => _message = _t(
            'Unable to connect. Your number has not been verified.',
            'تعذّر الاتصال. لم يتم توثيق رقمكِ.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_t('Private phone test', 'اختبار رقم الهاتف'))),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          _t(
            'Private testing only. This code is displayed here, not sent by SMS. Your number stays unverified and cannot be used to sign in or recover an account.',
            'للاختبار الخاص فقط. يظهر الرمز هنا ولا يُرسل برسالة نصية. يبقى رقمكِ غير موثّق ولا يُستخدم لتسجيل الدخول أو استعادة الحساب.',
          ),
        ),
        const SizedBox(height: 20),
        if (_done)
          Text(
            _t(
              'Test complete. Phone number saved as unverified.',
              'اكتمل الاختبار. حُفظ رقم الهاتف بصفته غير موثّق.',
            ),
          )
        else ...[
          TextField(
            controller: _phone,
            enabled: !_busy && _testCode == null,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: _t('Phone number', 'رقم الهاتف'),
            ),
          ),
          if (_testCode != null) ...[
            const SizedBox(height: 16),
            Text(
              '${_t('Test code', 'رمز الاختبار')}: $_testCode',
              textDirection: TextDirection.ltr,
            ),
            TextField(
              controller: _code,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: _t('Enter test code', 'أدخلي رمز الاختبار'),
              ),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _request(complete: true),
              child: Text(_t('Continue', 'متابعة')),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      setState(() {
                        _testCode = null;
                        _code.clear();
                      });
                    },
              child: Text(
                _t(
                  'Change number / request another code',
                  'تغيير الرقم / طلب رمز جديد',
                ),
              ),
            ),
          ] else
            FilledButton(
              onPressed: _busy ? null : () => _request(complete: false),
              child: Text(_t('Show test code', 'عرض رمز الاختبار')),
            ),
        ],
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (_message != null)
          Semantics(liveRegion: true, child: Text(_message!)),
      ],
    ),
  );
}
