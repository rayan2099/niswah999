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
/// `prayer_log` (W0-003) is included below. `pregnancy_milestones` was
/// removed from this export (Dormant Pregnancy Tracking Retirement wave,
/// 2026-09-06) — the table was never deployed to production, so this fetch
/// was silently failing the entire export for every user (a single
/// unhandled fetch error here aborts the whole `_load()` try block); the
/// feature that would have written to it was retired in full for being
/// unreachable/superseded, not merely deferred.
class DataExportScreen extends StatefulWidget {
  const DataExportScreen({super.key});

  @override
  State<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends State<DataExportScreen> {
  bool _loading = true;
  String? _error;
  String? _json;
  List<String> _partialFailureSections = const [];

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

    // Every section is fetched independently and failures are isolated
    // per-section (RR-001 data-export resilience audit, 2026-09-06) —
    // this replaces a single shared try block where one bad/unreachable
    // table aborted the entire export for every user (the exact live bug
    // `pregnancy_milestones` caused before it was removed, Dormant
    // Pregnancy Tracking Retirement wave). A transient failure on any one
    // table must never hide data the user could otherwise have exported.
    final export = <String, dynamic>{'exported_at': DateTime.now().toIso8601String()};
    final failedSections = <String>[];

    Future<void> fetchOneInto(
      String key,
      String table, {
      String idColumn = 'user_id',
    }) async {
      try {
        export[key] = await _fetchOne(client, table, userId, idColumn: idColumn);
      } catch (error, stack) {
        failedSections.add(key);
        AppErrorReporter.report(
          error,
          stack,
          context: 'DataExportScreen._load',
          feature: 'data_export',
          recordId: key,
        );
      }
    }

    Future<void> fetchManyInto(String key, String table) async {
      try {
        export[key] = await _fetchMany(client, table, userId);
      } catch (error, stack) {
        failedSections.add(key);
        AppErrorReporter.report(
          error,
          stack,
          context: 'DataExportScreen._load',
          feature: 'data_export',
          recordId: key,
        );
      }
    }

    await fetchOneInto('account', 'users');
    await fetchOneInto('profile', 'profiles', idColumn: 'id');
    await fetchOneInto('pregnancy_profile', 'pregnancy_profile');
    await fetchManyInto('cycle_entries', 'cycle_entries');
    await fetchManyInto('prayer_log', 'prayer_log');
    await fetchManyInto('community_posts', 'community_posts');
    await fetchManyInto('chat_threads', 'chat_threads');
    await fetchManyInto('chat_messages', 'chat_messages');

    // Explicit completeness marker — never silently omit a section that
    // failed; a consumer of this JSON (the user, or anyone they share it
    // with) must be able to tell a genuinely empty section from one that
    // simply couldn't be fetched this time.
    export['export_complete'] = failedSections.isEmpty;
    if (failedSections.isNotEmpty) {
      export['sections_unavailable'] = failedSections;
    }

    setState(() {
      _loading = false;
      _json = const JsonEncoder.withIndent('  ').convert(export);
      _error = null;
      _partialFailureSections = failedSections;
    });
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
                          'cycle, prayer, pregnancy, chat, and community '
                          'data. It does not include internal '
                          'safety-review records.',
                          'هذا تصدير تقني خام لبيانات حسابكِ ودورتكِ '
                          'وصلاتكِ وحملكِ ومحادثاتكِ ومحتوى '
                          'مجتمعكِ. لا يشمل سجلات المراجعة الداخلية '
                          'للسلامة.',
                        ),
                        style: const TextStyle(fontSize: 11.5, height: 1.5),
                      ),
                    ),
                    if (_partialFailureSections.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7E6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _pr(
                            'This export is incomplete: ${_partialFailureSections.join(", ")} '
                            'could not be loaded this time. Try exporting again '
                            'later to include them.',
                            'هذا التصدير غير مكتمل: تعذّر تحميل '
                            '${_partialFailureSections.join("، ")} في '
                            'هذه المرة. حاولي التصدير مرة أخرى لاحقاً '
                            'لتضمينها.',
                          ),
                          style: const TextStyle(fontSize: 11.5, height: 1.5),
                        ),
                      ),
                    ],
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
