import '../../../../core/storage/secure_local_store.dart';
import 'prediction_history_review_store.dart';

PredictionHistoryReviewStore createPredictionHistoryReviewStore() =>
    PredictionHistoryReviewStore(
      read: (owner) => SecureLocalStore.read(
        PredictionHistoryReviewStore.category,
        userId: owner,
      ),
      write: (owner, value) => SecureLocalStore.write(
        PredictionHistoryReviewStore.category,
        value,
        userId: owner,
      ),
    );

Future<void> clearPredictionHistoryReviewsForUser(String owner) async {
  await PredictionHistoryReviewStore.waitForPendingWrites(owner);
  await SecureLocalStore.clearForUser(
    PredictionHistoryReviewStore.category,
    owner,
  );
}
