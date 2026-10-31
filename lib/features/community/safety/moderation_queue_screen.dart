import 'package:flutter/material.dart';

import '../../../core/localization/app_locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import 'community_safety_models.dart';
import 'community_safety_repository.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// Moderators only (`users.role = 'admin'`; the RPCs refuse anyone else).
/// Lists open reports oldest first so nothing waits past the 24-hour
/// response promised in the community guidelines, with the three actions
/// the server supports.
class ModerationQueueScreen extends StatefulWidget {
  const ModerationQueueScreen({super.key, this.repository});

  final CommunitySafetyRepository? repository;

  @override
  State<ModerationQueueScreen> createState() => _ModerationQueueScreenState();
}

class _ModerationQueueScreenState extends State<ModerationQueueScreen> {
  CommunitySafetyRepository get _repository =>
      widget.repository ?? communitySafetyRepository;

  List<ModerationReport> _reports = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reports = await _repository.fetchModerationQueue();
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _t('Could not load reports.', 'تعذر تحميل البلاغات.');
      });
    }
  }

  Future<void> _resolve(
    ModerationReport report,
    ModerationAction action,
  ) async {
    try {
      await _repository.resolveReport(
        reportId: report.reportId,
        action: action,
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t('Could not apply that action.', 'تعذر تنفيذ الإجراء.'),
          ),
        ),
      );
    }
  }

  String _targetLabel(ReportTargetType type) => switch (type) {
    ReportTargetType.post => _t('Post', 'منشور'),
    ReportTargetType.comment => _t('Comment', 'تعليق'),
    ReportTargetType.message => _t('Private message', 'رسالة خاصة'),
    ReportTargetType.user => _t('Member', 'عضوة'),
  };

  String _age(DateTime createdAt) {
    final hours = DateTime.now().difference(createdAt.toLocal()).inHours;
    return hours < 1
        ? _t('under 1 hour ago', 'قبل أقل من ساعة')
        : _t('$hours h ago', 'قبل $hours ساعة');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('Moderation queue', 'قائمة الإشراف')),
        actions: [
          IconButton(
            tooltip: _t('Refresh', 'تحديث'),
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!))
            : _reports.isEmpty
            ? Center(
                child: Text(_t('No open reports.', 'لا توجد بلاغات مفتوحة.')),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _reports.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final report = _reports[index];
                    final overdue =
                        DateTime.now()
                            .difference(report.createdAt.toLocal())
                            .inHours >=
                        20;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_targetLabel(report.targetType)} · '
                              '${report.reason.label()} · '
                              '${_age(report.createdAt)}',
                              style: textTheme.labelLarge?.copyWith(
                                color: overdue ? AppColors.error : null,
                              ),
                            ),
                            if (report.openReportCount > 1 ||
                                report.targetHidden ||
                                report.targetUserSuspended)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  [
                                    if (report.openReportCount > 1)
                                      _t(
                                        '${report.openReportCount} reports',
                                        '${report.openReportCount} بلاغات',
                                      ),
                                    if (report.targetHidden)
                                      _t('hidden', 'مخفي'),
                                    if (report.targetUserSuspended)
                                      _t('member suspended', 'العضوة موقوفة'),
                                  ].join(' · '),
                                  style: textTheme.bodySmall,
                                ),
                              ),
                            if (report.contentSnapshot != null) ...[
                              const SizedBox(height: 8),
                              Text(report.contentSnapshot!),
                            ],
                            if (report.details != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _t(
                                  'Reporter: ${report.details}',
                                  'المُبلِّغة: ${report.details}',
                                ),
                                style: textTheme.bodySmall,
                              ),
                            ],
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () => _resolve(
                                    report,
                                    ModerationAction.dismiss,
                                  ),
                                  child: Text(_t('Dismiss', 'رفض البلاغ')),
                                ),
                                if (report.targetType != ReportTargetType.user)
                                  OutlinedButton(
                                    onPressed: () => _resolve(
                                      report,
                                      ModerationAction.removeContent,
                                    ),
                                    child: Text(_t('Remove', 'حذف المحتوى')),
                                  ),
                                FilledButton(
                                  onPressed: () => _resolve(
                                    report,
                                    ModerationAction.suspendUser,
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.error,
                                  ),
                                  child: Text(
                                    _t(
                                      'Remove and suspend',
                                      'حذف وإيقاف العضوة',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
