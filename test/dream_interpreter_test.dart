import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/dream_interpreter/domain/entities/dream_entry.dart';

void main() {
  group('Dream interpreter models', () {
    test('serializes and deserializes a dream entry', () {
      final now = DateTime(2026, 8, 18, 8, 45);
      final entry = DreamEntry(
        id: 'dream-1',
        userId: 'user-1',
        title: 'Flying over the sea',
        description: 'I was floating over a calm ocean and feeling peaceful.',
        mood: DreamMood.peaceful,
        tags: const ['water', 'calm'],
        createdAt: now,
        interpretation: 'This dream may reflect emotional clarity and a need for peace.',
        rating: 5,
      );

      final json = entry.toJson();
      final restored = DreamEntry.fromJson(json);

      expect(restored.id, 'dream-1');
      expect(restored.title, 'Flying over the sea');
      expect(restored.mood, DreamMood.peaceful);
      expect(restored.tags, ['water', 'calm']);
      expect(restored.rating, 5);
    });
  });
}
