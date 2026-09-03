import '../entities/dream_entry.dart';

abstract class DreamInterpreterRepository {
  Future<List<DreamEntry>> getEntries({required String userId});

  Future<DreamEntry> saveEntry({
    required String userId,
    required DreamEntry entry,
  });

  Future<void> deleteEntry({required String userId, required String entryId});
}
