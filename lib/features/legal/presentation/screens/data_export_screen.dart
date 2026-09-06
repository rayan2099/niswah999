import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/theme/app_theme.dart';

String _pr(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// A real, working personal-data export (PC-006) — the existing "Data
/// Export" only produced 4 curated PDF reports, not the user's actual raw
/// records. This fetches the caller's own rows (RLS already scopes every
/// query to `auth.uid()` — no service-role access, no other user's data
/// possible) across the tables this app's own inventory identified as
/// `REQUIRED_APPLICATION_OBJECT`, assembles them into portable JSON, and
/// lets the user copy it out. Deliberately excludes `flagged_conversations`
/// (a service-role-only internal safety-audit log with no user-facing RLS
/// read policy at all — not user-owned content to begin with) and any
/// internal/service metadata. **Partial, stated plainly in the UI**: does
/// not attempt a full account-level archive format — this is the safe
/// portion implementable now without further backend/schema changes.
/// `pregnancy_milestones` (W0-002, now a real table) and `prayer_log`
/// (W0-003) are both included below — this doc comment previously claimed
/// otherwise after W0-003 shipped without being updated; corrected here.
class DataExportScreen extends StatefulWidget {
  const DataExportScreen({super.key});

  @override
  State<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends State<DataExportScreen> {
  bool _loading = true;
  String? _error;
  String? _json;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = NiswahSupabase.clientOrNull;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) {
      setState(() {
        _loading = false;
        _error = _pr(
          'You must be signed in to export your data.',
          'يجب تسجيل الدخول لتصدير بياناتكِ.',
        );
      });
      return;
    }

    try {
      final export = <String, dynamic>{
        'exported_at': DateTime.now().toIso8601String(),
        'account': await _fetchOne(client, 'users', userId),
        'profile': await _fetchOne(client, 'profiles', userId, idColumn: 'id'),
        'pregnancy_profile': await _fetchOne(
          client,
          'pregnancy_profile',
          userId,
        ),
        'cycle_entries': await _fetchMany(client, 'cycle_entries', userId),
        'prayer_log': await _fetchMany(client, 'prayer_log', userId),
        'pregnancy_milestones': await _fetchMany(
          client,
          'pregnancy_milestones',
          userId,
        ),
        'community_posts': await _fetchMany(
          client,
          'community_posts',
          userId,
        ),
        'chat_threads': await _fetchMany(client, 'chat_threads', userId),
        'chat_messages': await _fetchMany(client, 'chat_messages', userId),
      };

      setState(() {
        _loading = false;
        _json = const JsonEncoder.withIndent('  ').convert(export);
      });
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        context: 'DataExportScreen._load',
        feature: 'data_export',
      );
      setState(() {
        _loading = false;
        _error = _pr(
          "Couldn't load your data. Please try again.",
          'تعذّر تحميل بياناتكِ. يُرجى المحاولة مرة أخرى.',
        );
      });
    }
  }

  Future<Map<String, dynamic>?> _fetchOne(
    dynamic client,
    String table,
    String userId, {
    String idColumn = 'user_id',
  }) async {
    final row = await client
        .from(table)
        .select()
        .eq(idColumn, userId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row as Map);
  }

  Future<List<Map<String, dynamic>>> _fetchMany(
    dynamic client,
    String table,
    String userId,
  ) async {
    final rows = await client.from(table).select().eq('user_id', userId);
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text(_pr('Export My Data', 'تصدير بياناتي'))),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _pr(
                          'This is a raw technical export of your account, '
                          'cycle, prayer, pregnancy-tracking, chat, and '
                          'community data. It does not include internal '
                          'safety-review records.',
                          'هذا تصدير تقني خام لبيانات حسابكِ ودورتكِ '
                          'وصلاتكِ ومتابعة حملكِ ومحادثاتكِ ومحتوى '
                          'مجتمعكِ. لا يشمل سجلات المراجعة الداخلية '
                          'للسلامة.',
                        ),
                        style: const TextStyle(fontSize: 11.5, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _json ?? '',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: _json ?? ''),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                _pr(
                                  'Copied to clipboard.',
                                  'تم النسخ إلى الحافظة.',
                                ),
                              ),
                            ),
                          );
                        }
                      },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: AppColors.textPrimary,
                      ),
                      child: Text(_pr('Copy to Clipboard', 'نسخ إلى الحافظة')),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
