/// Serializes a read/modify/write transaction for one category and owner
/// within this app process. Different owners/categories remain independent.
/// This is not a cross-device or cross-process database transaction.
class ScopedMutationQueue {
  ScopedMutationQueue._();

  static final Map<(String, String), Future<void>> _tails = {};

  static Future<T> run<T>({
    required String category,
    required String owner,
    required Future<T> Function() action,
  }) {
    final key = (category, owner);
    final previous = _tails[key] ?? Future<void>.value();
    final work = previous.then((_) => action());
    // A failed transaction must fail its caller, but never poison the queue.
    final tail = work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _tails[key] = tail;
    return work.whenComplete(() {
      if (identical(_tails[key], tail)) _tails.remove(key);
    });
  }
}
