import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/gemini_service.dart';
import '../../data/repositories/dream_interpreter_repository_impl.dart';
import '../../domain/entities/dream_entry.dart';
import '../../domain/repositories/dream_interpreter_repository.dart';

const String _dreamInterpreterSystemPrompt = '''
You are an expert Islamic dream interpreter grounded strictly in classical traditional frameworks (such as the methodologies and symbol dictionaries of Ibn Sirin and Al-Nabulsi).

Your core objective is to provide deeply personalized, accurate, and spiritually grounded interpretations while avoiding any claim of knowing the unseen (Al-Ghaib).

Follow these rules for every interpretation session:

1. **Interactive Clarification First:**
- Do not immediately jump to a final, rigid interpretation if the dream description lacks crucial context.
- Ask 2 to 3 targeted, concise follow-up questions to understand the user's emotional state during the dream, recurring patterns, specific sensory details (like colors or surroundings), or relevant real-world life situations that might influence the symbolism.

2. **Classical Grounding & Personalization:**
- Once context is gathered, interpret the core symbols using established classical Islamic dream interpretation principles.
- Tailor the meaning dynamically based on the user's specific life context, ensuring the advice remains uplifting, constructive, and spiritually sound.

3. **Tone and Boundaries:**
- Maintain a wise, empathetic, and reassuring tone.
- Always include a gentle reminder that dreams are sources of glad tidings, warning, or reflection, but never absolute predetermined fates or definitive legislative rulings.

4. **Formatting and Length:**
- Write in plain prose only. Never use markdown syntax: no #, ##, ###, **, *, or numbered/bulleted list characters. The app displays raw text, not rendered markdown.
- Keep clarifying questions to 2-3 short sentences.
- Keep the final interpretation short and focused: a few short paragraphs covering the core symbolism and the closing reminder, not an exhaustive breakdown of every element.

5. **Language:**
- Always reply in the same language the user's most recent message is written in (e.g. Arabic in, Arabic out; English in, English out). Never switch languages on your own.
''';

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
      final result = await GeminiService.instance.generateText(
        prompt: _buildTranscriptPrompt(),
        systemInstruction: _dreamInterpreterSystemPrompt,
      );
      _transcript.add(DreamMessage(DreamMessageRole.assistant, result.text));

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
        interpretation: result.text,
      );

      entries = [entry, ...entries.where((item) => item.id != entryId)];
      notifyListeners();

      try {
        final saved = await _repository.saveEntry(userId: userId, entry: entry);
        entries = [saved, ...entries.where((item) => item.id != entryId)];
      } catch (error) {
        debugPrint('[DreamInterpreter] saveEntry failed: $error');
        warningMessage = 'The interpretation is shown, but it could not be saved to your history.';
      }
    } catch (error) {
      // The failed turn has no reply yet; drop it so a retry doesn't
      // resend it twice in a row with nothing in between.
      _transcript.removeLast();
      errorMessage = error.toString();
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
