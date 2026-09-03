import '../../core/network/supabase_client.dart';
import 'data/repositories/mock_private_messaging_repository.dart';
import 'data/repositories/private_messaging_repository.dart';
import 'domain/repositories/private_messaging_repository_base.dart';

PrivateMessagingRepositoryBase? _override;

/// Test-only (or DI) override for the private messaging repository.
set privateMessagingRepositoryOverride(PrivateMessagingRepositoryBase repo) =>
    _override = repo;

/// Lazily-resolved access point for the private messaging repository.
///
/// Resolution order:
/// 1. Explicit override (used by widget tests).
/// 2. Supabase-backed implementation when Supabase is initialized.
/// 3. In-memory mock with demo data, so the UI is explorable in the
///    simulator without a backend or signed-in user.
PrivateMessagingRepositoryBase get privateMessagingRepository {
  if (_override != null) return _override!;
  final client = NiswahSupabase.clientOrNull;
  if (client == null) return MockPrivateMessagingRepository();
  return PrivateMessagingRepository(client);
}
