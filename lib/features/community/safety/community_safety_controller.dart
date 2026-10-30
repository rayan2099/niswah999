import 'package:flutter/foundation.dart';

import 'community_safety_models.dart';
import 'community_safety_repository.dart';

/// App-wide, in-memory view of the signed-in member's community safety
/// state: who she has blocked, whether she accepted the current terms,
/// whether she is a moderator.
///
/// The database is the authority (RLS hides blocked members' posts and
/// comments; triggers refuse writes without terms, from suspended members,
/// or between blocked members). This controller only makes the UI react
/// immediately, e.g. a blocked member's posts disappear from the feed the
/// moment she is blocked, without waiting for a reload.
class CommunitySafetyController extends ChangeNotifier {
  CommunitySafetyController({CommunitySafetyRepository? repository})
    : _repositoryOverride = repository;

  static CommunitySafetyController instance = CommunitySafetyController();

  final CommunitySafetyRepository? _repositoryOverride;
  CommunitySafetyRepository get _repository =>
      _repositoryOverride ?? communitySafetyRepository;

  List<BlockedMember> _blocked = const [];
  Set<String> _blockedIds = const {};
  bool? _termsAccepted;
  bool _isModerator = false;
  bool _loaded = false;

  List<BlockedMember> get blockedMembers => _blocked;
  bool isBlocked(String? userId) =>
      userId != null && _blockedIds.contains(userId);

  /// Null until known (not loaded yet, or the check failed).
  bool? get termsAccepted => _termsAccepted;
  bool get isModerator => _isModerator;
  bool get isLoaded => _loaded;

  /// Loads blocks, terms state and moderator flag. Failures leave the
  /// previous values in place; the server still enforces everything.
  Future<void> load() async {
    try {
      final blocked = await _repository.fetchBlockedMembers();
      _setBlocked(blocked);
    } catch (_) {}
    try {
      _termsAccepted = await _repository.hasAcceptedCurrentTerms();
    } catch (_) {}
    try {
      _isModerator = await _repository.isModerator();
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> acceptTerms() async {
    await _repository.acceptCurrentTerms();
    _termsAccepted = true;
    notifyListeners();
  }

  /// Re-reads terms state when it is not known yet. Returns it, or null
  /// if the server could not be reached.
  Future<bool?> refreshTermsAccepted() async {
    if (_termsAccepted == true) return true;
    try {
      _termsAccepted = await _repository.hasAcceptedCurrentTerms();
      notifyListeners();
    } catch (_) {}
    return _termsAccepted;
  }

  Future<void> block({required String userId, String? displayName}) async {
    await _repository.blockMember(userId: userId, displayName: displayName);
    if (!isBlocked(userId)) {
      _setBlocked([
        BlockedMember(
          userId: userId,
          displayName: displayName,
          blockedAt: DateTime.now(),
        ),
        ..._blocked,
      ]);
    }
    notifyListeners();
  }

  Future<void> unblock(String userId) async {
    await _repository.unblockMember(userId);
    _setBlocked(_blocked.where((member) => member.userId != userId).toList());
    notifyListeners();
  }

  Future<void> report({
    required ReportTargetType targetType,
    required String targetId,
    required ReportReason reason,
    String? details,
  }) => _repository.report(
    targetType: targetType,
    targetId: targetId,
    reason: reason,
    details: details,
  );

  /// Called on sign-out / account switch so the next account never sees
  /// the previous one's blocks or moderator flag.
  void resetInMemory() {
    _setBlocked(const []);
    _termsAccepted = null;
    _isModerator = false;
    _loaded = false;
    notifyListeners();
  }

  void _setBlocked(List<BlockedMember> blocked) {
    _blocked = List.unmodifiable(blocked);
    _blockedIds = {for (final member in blocked) member.userId};
  }
}
