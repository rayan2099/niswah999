import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/educational_library/domain/entities/resource_item.dart';

void main() {
  group('Educational library models', () {
    test('serializes and deserializes a resource item', () {
      final now = DateTime(2026, 8, 18, 10, 15);
      final item = ResourceItem(
        id: 'resource-1',
        category: ResourceCategory.spouse,
        title: 'A caring guide for partners',
        summary: 'Support each other through health and prayer rhythms.',
        content: 'Care is shown through listening, planning, and empathy.',
        author: 'Niswah Team',
        readMinutes: 6,
        tags: const ['support', 'partner'],
        isSpouseGuide: true,
        createdAt: now,
      );

      final json = item.toJson();
      final restored = ResourceItem.fromJson(json);

      expect(restored.id, 'resource-1');
      expect(restored.category, ResourceCategory.spouse);
      expect(restored.title, 'A caring guide for partners');
      expect(restored.isSpouseGuide, isTrue);
      expect(restored.tags, ['support', 'partner']);
    });
  });
}
