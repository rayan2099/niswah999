import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/supabase_client.dart';
import 'community_safety_models.dart';
import 'community_terms.dart';

/// Reporting, blocking, terms acceptance and moderation for Community and
/// private messages. Server rules live in
/// supabase/migrations/20261030090000_community_ugc_safety.sql.
abstract class CommunitySafetyRepository {
  Future<bool> hasAcceptedCurrentTerms();

  Future<void> acceptCurrentTerms();

  /// Whether the current member is suspended from Community.
  Future<bool> isSuspended();

  Future<List<BlockedMember>> fetchBlockedMembers();

  Future<void> blockMember({required String userId, String? displayName});

  Future<void> unblockMember(String userId);

  /// Files (or returns the existing) report by the current member.
  Future<void> report({
    required ReportTargetType targetType,
    required String targetId,
    required ReportReason reason,
    String? details,
  });

  /// True when the signed-in account is a moderator (`users.role = admin`).
  Future<bool> isModerator();

  Future<List<ModerationReport>> fetchModerationQueue();

  Future<void> resolveReport({
    required String reportId,
    required ModerationAction action,
    String? note,
  });
}

class SupabaseCommunitySafetyRepository implements CommunitySafetyRepository {
  SupabaseCommunitySafetyRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Not signed in');
    return id;
  }

  @override
  Future<bool> hasAcceptedCurrentTerms() async {
    final row = await _client
        .from('community_terms_acceptances')
        .select('accepted_at')
        .eq('user_id', _userId)
        .eq('terms_version', CommunityTerms.version)
        .maybeSingle();
    return row != null;
  }

  @override
  Future<void> acceptCurrentTerms() async {
    try {
      await _client.from('community_terms_acceptances').insert({
        'user_id': _userId,
        'terms_version': CommunityTerms.version,
      });
    } on PostgrestException catch (error) {
      // Already accepted on another device.
      if (error.code != '23505') rethrow;
    }
  }

  @override
  Future<bool> isSuspended() async {
    final row = await _client
        .from('community_suspensions')
        .select('user_id')
        .eq('user_id', _userId)
        .maybeSingle();
    return row != null;
  }

  @override
  Future<List<BlockedMember>> fetchBlockedMembers() async {
    final rows = await _client
        .from('user_blocks')
        .select('blocked_id, blocked_display_name, created_at')
        .eq('blocker_id', _userId)
        .order('created_at', ascending: false);
    return (rows as List<dynamic>)
        .map(
          (row) => BlockedMember(
            userId: row['blocked_id'] as String,
            displayName: row['blocked_display_name'] as String?,
            blockedAt: DateTime.parse(row['created_at'] as String),
          ),
        )
        .toList();
  }

  @override
  Future<void> blockMember({
    required String userId,
    String? displayName,
  }) async {
    final name = displayName?.trim();
    try {
      await _client.from('user_blocks').insert({
        'blocker_id': _userId,
        'blocked_id': userId,
        'blocked_display_name': name == null || name.isEmpty
            ? null
            : (name.length > 80 ? name.substring(0, 80) : name),
      });
    } on PostgrestException catch (error) {
      // Already blocked (double tap, or from another device).
      if (error.code != '23505') rethrow;
    }
  }

  @override
  Future<void> unblockMember(String userId) async {
    await _client
        .from('user_blocks')
        .delete()
        .eq('blocker_id', _userId)
        .eq('blocked_id', userId);
  }

  @override
  Future<void> report({
    required ReportTargetType targetType,
    required String targetId,
    required ReportReason reason,
    String? details,
  }) async {
    await _client.rpc(
      'report_community_content',
      params: {
        'p_target_type': targetType.name,
        'p_target_id': targetId,
        'p_reason': reason.dbValue,
        'p_details': details,
      },
    );
  }

  @override
  Future<bool> isModerator() async {
    final row = await _client
        .from('users')
        .select('role')
        .eq('id', _userId)
        .maybeSingle();
    return row?['role'] == 'admin';
  }

  @override
  Future<List<ModerationReport>> fetchModerationQueue() async {
    final rows = await _client.rpc(
      'community_moderation_queue',
      params: {'p_limit': 200},
    );
    return (rows as List<dynamic>)
        .map((row) => ModerationReport.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  @override
  Future<void> resolveReport({
    required String reportId,
    required ModerationAction action,
    String? note,
  }) async {
    await _client.rpc(
      'resolve_community_report',
      params: {
        'p_report_id': reportId,
        'p_action': action.dbValue,
        'p_note': note,
      },
    );
  }
}

/// Used when Supabase is not configured (offline preview, widget tests):
/// keeps state in memory so every flow is still explorable.
class InMemoryCommunitySafetyRepository implements CommunitySafetyRepository {
  bool termsAccepted = false;
  bool suspended = false;
  bool moderator = false;
  final List<BlockedMember> blocked = [];
  final List<
    ({
      ReportTargetType targetType,
      String targetId,
      ReportReason reason,
      String? details,
    })
  >
  reports = [];
  final List<ModerationReport> queue = [];
  final List<({String reportId, ModerationAction action})> resolutions = [];

  @override
  Future<bool> hasAcceptedCurrentTerms() async => termsAccepted;

  @override
  Future<void> acceptCurrentTerms() async => termsAccepted = true;

  @override
  Future<bool> isSuspended() async => suspended;

  @override
  Future<List<BlockedMember>> fetchBlockedMembers() async => [...blocked];

  @override
  Future<void> blockMember({
    required String userId,
    String? displayName,
  }) async {
    if (blocked.any((member) => member.userId == userId)) return;
    blocked.insert(
      0,
      BlockedMember(
        userId: userId,
        displayName: displayName,
        blockedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> unblockMember(String userId) async =>
      blocked.removeWhere((member) => member.userId == userId);

  @override
  Future<void> report({
    required ReportTargetType targetType,
    required String targetId,
    required ReportReason reason,
    String? details,
  }) async {
    reports.add((
      targetType: targetType,
      targetId: targetId,
      reason: reason,
      details: details,
    ));
  }

  @override
  Future<bool> isModerator() async => moderator;

  @override
  Future<List<ModerationReport>> fetchModerationQueue() async => [...queue];

  @override
  Future<void> resolveReport({
    required String reportId,
    required ModerationAction action,
    String? note,
  }) async {
    resolutions.add((reportId: reportId, action: action));
    final target = queue.where((r) => r.reportId == reportId).firstOrNull;
    if (target == null) return;
    queue.removeWhere(
      (r) => r.targetType == target.targetType && r.targetId == target.targetId,
    );
  }
}

CommunitySafetyRepository? _override;

/// Test-only (or DI) override, matching `privateMessagingRepositoryOverride`.
set communitySafetyRepositoryOverride(CommunitySafetyRepository? repo) =>
    _override = repo;

CommunitySafetyRepository get communitySafetyRepository {
  if (_override != null) return _override!;
  final client = NiswahSupabase.clientOrNull;
  if (client == null) return _offline;
  return SupabaseCommunitySafetyRepository(client);
}

final InMemoryCommunitySafetyRepository _offline =
    InMemoryCommunitySafetyRepository();
