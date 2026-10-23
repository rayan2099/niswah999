import '../entities/private_message.dart';

/// Optional live capability; read-only/mocked repositories need not emulate it.
abstract interface class PrivateMessagingRealtime {
  void Function() watchConversation(
    String id,
    void Function(PrivateMessage) onMessage, {
    void Function()? onResync,
  });
  void Function() watchChanges(void Function() onChange);
}
