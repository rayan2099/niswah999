# Niswah parity checklist

## Architecture and security requirements

- [ ] Secure environment loading for local, test, and production builds
- [ ] Flutter app bootstrap with Supabase initialization and app-level configuration
- [ ] Clean Architecture folder structure under `core/` and `features/`
- [ ] Repository pattern for authentication and user data access
- [ ] RLS-first data access that never exposes the Supabase service role secret in client code
- [ ] User-scoped auth flows and profile retrieval using the authenticated session only

## Security guardrails

- Client apps must use the anonymous key only.
- The service role key must never be shipped to the device or embedded in Flutter code.
- All table access must rely on Supabase Row Level Security and the currently signed-in user's session.
- Any server-side operations that require elevated privileges must live in a trusted backend or Edge Function.
