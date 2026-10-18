import 'dart:convert';
import 'dart:async';

import '../../domain/entities/prediction_history_review.dart';

/// Encrypted persistence is supplied by the platform adapter. Explicit owner
/// arguments prevent an awaited account switch redirecting sensitive writes.
class PredictionHistoryReviewStore {
  PredictionHistoryReviewStore({required this.read, required this.write});
  static const category = 'prediction_history_reviews_v1';
  final Future<String?> Function(String userId) read;
  final Future<void> Function(String userId, String value) write;
  static final Map<String, Future<void>> _pending = {};
  static final _changes = StreamController<String>.broadcast();
  static Stream<String> get changes => _changes.stream;

  static Future<void> waitForPendingWrites(String userId) async {
    try {
      await _pending[userId];
    } catch (_) {
      // Cleanup must still delete a partially written value after failure.
    }
  }

  Future<List<PredictionHistoryReview>> load(String userId) async {
    final raw = await read(userId);
    if (raw == null) return const [];
    // A failed/malformed read must not look like confirmed empty history.
    final payload = jsonDecode(raw) as Map<String, dynamic>;
    if (payload['version'] != 1) {
      throw const FormatException('Unknown review schema');
    }
    return (payload['reviews'] as List)
        .map(
          (row) =>
              PredictionHistoryReview.fromJson(row as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> save(String userId, PredictionHistoryReview review) async {
    PredictionHistoryReview.fromJson(review.toJson());
    // Serialize read-modify-write across screen instances in this process.
    final previous = _pending[userId] ?? Future<void>.value();
    final operation = previous.catchError((Object _) {}).then((_) async {
      final existing = await load(userId);
      final next = [
        for (final item in existing)
          if (item.key != review.key) item,
        review,
      ];
      final raw = jsonEncode({
        'version': 1,
        'reviews': next.map((r) => r.toJson()).toList(),
      });
      await write(userId, raw);
      if (await read(userId) != raw) {
        throw StateError('Review save could not be verified');
      }
      _changes.add(userId);
    });
    _pending[userId] = operation;
    try {
      await operation;
    } finally {
      if (identical(_pending[userId], operation)) _pending.remove(userId);
    }
  }
}
