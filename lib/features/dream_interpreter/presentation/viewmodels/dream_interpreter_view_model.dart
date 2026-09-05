import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/app_error_reporter.dart';
import '../../../../core/network/supabase_client.dart';
import '../../data/repositories/dream_interpreter_repository_impl.dart';
import '../../domain/entities/dream_entry.dart';
import '../../domain/repositories/dream_interpreter_repository.dart';

enum DreamMessageRole { user, assistant }

class DreamMessage {
  const DreamMessage(this.role, this.content);
  final DreamMessageRole role;
  final String content;
}

class DreamInterpreterViewModel extends ChangeNotifier {
  DreamInterpreterViewModel({DreamInterpreterRepository? repository})
    : _repository = repository ?? DreamInterpreterRepositoryImpl();

  final DreamInterpreterRepository _repository;

  bool isLoading = false;
  bool isSubmitting = false;
  String? errorMessage;
  String? warningMessage;
  List<DreamEntry> entries = const <DreamEntry>[];

  // Holds the back-and-forth for the dream currently being discussed on this
  // screen, since Gemini's /interactions endpoint takes a single prompt
  // string with no history field of its own — each call resends the whole
  // transcript so far. Reset per screen open (a fresh view model), so a new
  // visit always starts a new dream rather than bolting onto an old one.
  final List<DreamMessage> _transcript = [];
  String? _activeEntryId;
  bool _isResumedFromHistory = false;

  /// The full back-and-forth for the dream currently on screen, for
  /// rendering as a real chat thread.
  List<DreamMessage> get transcript => List.unmodifiable(_transcript);

  /// True while `activeEntry` was picked back up from a previous session
  /// (rather than started fresh just now), so the screen can label it.
  bool get isResumedConversation => _isResumedFromHistory;

  /// The entry for the dream currently being discussed on this screen, or
  /// null before the first message of a new conversation gets a reply.
  DreamEntry? get activeEntry {
    final id = _activeEntryId;
    if (id == null) return null;
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  Future<void> loadEntries({required String userId}) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      entries = await _repository.getEntries(userId: userId);
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Loads a past dream back into the active conversation. Only the opening
  /// description and final reply were ever persisted, not the intermediate
  /// clarifying questions, so that's what the transcript is seeded with.
  void resumeEntry(DreamEntry entry) {
    _activeEntryId = entry.id;
    _isResumedFromHistory = true;
    _transcript
      ..clear()
      ..add(DreamMessage(DreamMessageRole.user, entry.description))
      ..add(DreamMessage(DreamMessageRole.assistant, entry.interpretation ?? ''));
    notifyListeners();
  }

  Future<void> deleteEntry({
    required String userId,
    required String entryId,
  }) async {
    try {
      await _repository.deleteEntry(userId: userId, entryId: entryId);
      entries = entries.where((entry) => entry.id != entryId).toList();
      if (_activeEntryId == entryId) {
        _activeEntryId = null;
        _transcript.clear();
      }
      notifyListeners();
    } catch (error) {
      errorMessage = error.toString();
      notifyListeners();
    }
  }

  /// Starts a fresh dream conversation, leaving the previous one (if any)
  /// as-is in `entries` for the history list to still show.
  void startNewDream() {
    _activeEntryId = null;
    _isResumedFromHistory = false;
    _transcript.clear();
    notifyListeners();
  }

  Future<void> sendMessage({
    required String userId,
    required String message,
  }) async {
    final cleanMessage = message.trim();
    if (cleanMessage.isEmpty) return;

    isSubmitting = true;
    errorMessage = null;
    warningMessage = null;
    _isResumedFromHistory = false;
    _transcript.add(DreamMessage(DreamMessageRole.user, cleanMessage));
    notifyListeners();

    try {
      final client = NiswahSupabase.clientOrNull;
      if (client == null) {
        throw StateError('Supabase is not initialized.');
      }
      final response = await client.functions.invoke(
        'dream-interpreter-chat',
        body: {'prompt': _buildTranscriptPrompt()},
      );
      final data = response.data;
      if (data is! Map || response.status != 200) {
        final error = data is Map ? data['error']?.toString() : null;
        throw StateError(
          error ?? 'Dream interpreter service failed (${response.status}).',
        );
      }
      final replyText = data['text']?.toString() ?? '';
      _transcript.add(DreamMessage(DreamMessageRole.assistant, replyText));

      // dream_entries.id is a Postgres UUID column, so this has to be a
      // real UUID rather than a readable string, or every insert fails
      // with an "invalid input syntax for type uuid" error.
      final entryId = _activeEntryId ??= const Uuid().v4();
      final firstMessage = _transcript.first.content;
      final entry = DreamEntry(
        id: entryId,
        userId: userId,
        title: firstMessage.length > 60
            ? '${firstMessage.substring(0, 60)}…'
            : firstMessage,
        description: firstMessage,
        mood: DreamMood.mysterious,
        tags: const <String>[],
        createdAt: DateTime.now(),
        interpretation: replyText,
      );

      entries = [entry, ...entries.where((item) => item.id != entryId)];
      notifyListeners();

      try {
        final saved = await _repository.saveEntry(userId: userId, entry: entry);
        entries = [saved, ...entries.where((item) => item.id != entryId)];
      } catch (error, stack) {
        AppErrorReporter.report(
          error,
          stack,
          context: 'DreamInterpreterViewModel.saveEntry',
          feature: 'dream_interpreter',
          recordId: entryId,
        );
        warningMessage = 'The interpretation is shown, but it could not be saved to your history.';
      }
    } catch (error, stack) {
      // The failed turn has no reply yet; drop it so a retry doesn't
      // resend it twice in a row with nothing in between.
      _transcript.removeLast();
      errorMessage = error.toString();
      AppErrorReporter.report(
        error,
        stack,
        context: 'DreamInterpreterViewModel.sendMessage',
      );
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  String _buildTranscriptPrompt() {
    final buffer = StringBuffer();
    for (final turn in _transcript) {
      buffer.writeln(
        '${turn.role == DreamMessageRole.user ? 'User' : 'Assistant'}: ${turn.content}',
      );
    }
    buffer.write('Assistant:');
    return buffer.toString();
  }
}
