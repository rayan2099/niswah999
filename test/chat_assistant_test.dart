import 'package:flutter_test/flutter_test.dart';
import 'package:niswah/features/ai_assistant/domain/entities/chat_message.dart';
import 'package:niswah/features/ai_assistant/domain/entities/chat_thread.dart';

void main() {
  group('Dr. Niswah chat models', () {
    test('serializes and deserializes chat threads', () {
      final now = DateTime(2026, 8, 18, 9, 30);
      final thread = ChatThread(
        id: 'thread-1',
        userId: 'user-1',
        title: 'Wellness check-in',
        threadType: ChatThreadType.drNiswah,
        status: ChatThreadStatus.active,
        metadata: {'source': 'mobile'},
        createdAt: now,
        updatedAt: now,
      );

      final json = thread.toJson();
      final restored = ChatThread.fromJson(json);

      expect(restored.id, 'thread-1');
      expect(restored.title, 'Wellness check-in');
      expect(restored.threadType, ChatThreadType.drNiswah);
      expect(restored.metadata['source'], 'mobile');
    });

    test('serializes and deserializes chat messages', () {
      final now = DateTime(2026, 8, 18, 9, 31);
      final message = ChatMessage(
        id: 'msg-1',
        threadId: 'thread-1',
        userId: 'user-1',
        role: ChatRole.user,
        content: 'How can I support my cycle this week?',
        metadata: {'tone': 'calm'},
        createdAt: now,
      );

      final json = message.toJson();
      final restored = ChatMessage.fromJson(json);

      expect(restored.threadId, 'thread-1');
      expect(restored.content, 'How can I support my cycle this week?');
      expect(restored.role, ChatRole.user);
      expect(restored.metadata['tone'], 'calm');
    });
  });
}
