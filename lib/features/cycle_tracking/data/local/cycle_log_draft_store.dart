import 'dart:convert';

import '../../../../core/storage/secure_local_store.dart';

/// What she had entered in the day-log sheet when her session ended
/// (journey NJ-013).
///
/// A draft is kept only when the sheet closed because the signed-in
/// account changed or the session ended, never when she closed it
/// herself. It is stored encrypted under the account that typed it, so it
/// is only ever offered back to that same account, and only for the same
/// day and entry. Nothing in it is saved as a record until she restores
/// it and taps Save.
class CycleLogDraft {
  const CycleLogDraft({
    required this.formKey,
    required this.values,
    required this.savedAt,
  });

  /// Which sheet the draft belongs to: mode, day and entry (or "new").
  final String formKey;

  /// The sheet's own field values, as the sheet wrote them.
  final Map<String, Object?> values;
  final DateTime savedAt;

  Map<String, Object?> toJson() => {
    'form_key': formKey,
    'values': values,
    'saved_at': savedAt.toUtc().toIso8601String(),
  };

  static CycleLogDraft? fromJson(Object? json) {
    if (json is! Map) return null;
    final formKey = json['form_key'];
    final values = json['values'];
    final savedAt = DateTime.tryParse('${json['saved_at']}');
    if (formKey is! String || values is! Map || savedAt == null) return null;
    return CycleLogDraft(
      formKey: formKey,
      values: Map<String, Object?>.from(values),
      savedAt: savedAt,
    );
  }
}

/// One draft per account; a newer one replaces the older.
abstract final class CycleLogDraftStore {
  static const category = 'cycle_log_draft';

  static Future<CycleLogDraft?> read(String userId) async {
    final raw = await SecureLocalStore.read(category, userId: userId);
    if (raw == null) return null;
    try {
      return CycleLogDraft.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  // The deletion marker replaces the health payload in the same encrypted
  // account slot. It survives app restart and contains no form values.
  static const _deleted = '{"account_deleted":true}';

  static String _queueKey(String userId) => '$category|$userId';

  static Future<void> write(String userId, CycleLogDraft draft) =>
      SecureLocalStore.serialized(_queueKey(userId), () async {
        if (await SecureLocalStore.read(category, userId: userId) == _deleted) {
          return;
        }
        await SecureLocalStore.write(
          category,
          jsonEncode(draft.toJson()),
          userId: userId,
        );
      });

  /// Ordinary discard/save cleanup must not remove a deletion fence.
  static Future<void> clearForUser(String userId) =>
      SecureLocalStore.serialized(_queueKey(userId), () async {
        if (await SecureLocalStore.read(category, userId: userId) == _deleted) {
          return;
        }
        await SecureLocalStore.clearForUser(category, userId);
      });

  /// Used only after confirmed account deletion. Cleanup runs before local
  /// sign-out; disposing the sheet on that sign-out may enqueue a late
  /// draft write. Serialize with writes and retain a durable fence so
  /// neither that write nor a later callback can restore deleted content.
  static Future<void> clearForDeletedUser(String userId) =>
      SecureLocalStore.serialized(
        _queueKey(userId),
        () => SecureLocalStore.write(category, _deleted, userId: userId),
      );
}
