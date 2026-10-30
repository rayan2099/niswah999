import '../../../core/localization/app_locale_controller.dart';

String _t(String en, String ar) => AppLocaleController.instance.text(en, ar);

/// What a report is about. Names match `community_reports.target_type`
/// (supabase/migrations/20261030090000_community_ugc_safety.sql).
enum ReportTargetType { post, comment, message, user }

/// Why something was reported. Names (via [dbValue]) match the
/// `community_reports_reason_check` constraint.
enum ReportReason {
  harassment,
  hate,
  sexual,
  violence,
  selfHarm,
  spam,
  misinformation,
  other;

  String get dbValue => this == ReportReason.selfHarm ? 'self_harm' : name;

  static ReportReason fromDb(String value) => ReportReason.values.firstWhere(
    (reason) => reason.dbValue == value,
    orElse: () => ReportReason.other,
  );

  String label() => switch (this) {
    ReportReason.harassment => _t('Harassment or bullying', 'تحرّش أو تنمّر'),
    ReportReason.hate => _t(
      'Hate speech or discrimination',
      'خطاب كراهية أو تمييز',
    ),
    ReportReason.sexual => _t(
      'Sexual or explicit content',
      'محتوى جنسي أو فاضح',
    ),
    ReportReason.violence => _t('Threats or violence', 'تهديد أو عنف'),
    ReportReason.selfHarm => _t(
      'Self-harm or suicide',
      'إيذاء النفس أو الانتحار',
    ),
    ReportReason.spam => _t('Spam or scam', 'رسائل مزعجة أو احتيال'),
    ReportReason.misinformation => _t(
      'Harmful medical or religious misinformation',
      'معلومات طبية أو دينية مضللة وضارة',
    ),
    ReportReason.other => _t('Something else', 'سبب آخر'),
  };
}

/// What a moderator does with an open report. Names match
/// `resolve_community_report(p_action)`.
enum ModerationAction {
  dismiss,
  removeContent,
  suspendUser;

  String get dbValue => switch (this) {
    ModerationAction.dismiss => 'dismiss',
    ModerationAction.removeContent => 'remove_content',
    ModerationAction.suspendUser => 'suspend_user',
  };
}

/// A member the current user has blocked.
class BlockedMember {
  const BlockedMember({
    required this.userId,
    required this.displayName,
    required this.blockedAt,
  });

  final String userId;
  final String? displayName;
  final DateTime blockedAt;
}

/// One open report as `community_moderation_queue()` returns it.
class ModerationReport {
  const ModerationReport({
    required this.reportId,
    required this.createdAt,
    required this.targetType,
    required this.targetId,
    required this.targetUserId,
    required this.reason,
    required this.details,
    required this.contentSnapshot,
    required this.openReportCount,
    required this.targetHidden,
    required this.targetUserSuspended,
  });

  factory ModerationReport.fromJson(Map<String, dynamic> json) =>
      ModerationReport(
        reportId: json['report_id'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        targetType: ReportTargetType.values.byName(
          json['target_type'] as String,
        ),
        targetId: json['target_id'] as String,
        targetUserId: json['target_user_id'] as String?,
        reason: ReportReason.fromDb(json['reason'] as String),
        details: json['details'] as String?,
        contentSnapshot: json['content_snapshot'] as String?,
        openReportCount: (json['open_report_count'] as num?)?.toInt() ?? 1,
        targetHidden: json['target_hidden'] as bool? ?? false,
        targetUserSuspended: json['target_user_suspended'] as bool? ?? false,
      );

  final String reportId;
  final DateTime createdAt;
  final ReportTargetType targetType;
  final String targetId;
  final String? targetUserId;
  final ReportReason reason;
  final String? details;
  final String? contentSnapshot;
  final int openReportCount;
  final bool targetHidden;
  final bool targetUserSuspended;
}
