# Password recovery

The email sign-in sheet can request a recovery email using the existing Supabase
repository. The response does not indicate whether an account exists. The link
redirects to `niswah://login-callback`; the Supabase auth recovery event routes
the user to a new-password form before normal authenticated navigation resumes.
On a successful password update the recovery gate is cleared. Passwords must
match and contain at least eight characters; backend password policy still
applies. Phone-only accounts are not covered by this email flow.

Recovery requires the exact callback to be allowed in the target Supabase
project, and functioning email delivery. The app must be opened on the device
which initiated recovery if PKCE is enabled. Test delivery and the link with
synthetic accounts in each environment, including cold and warm app startup,
expired or reused links, account switching, and both mobile platforms before
release. A successful compile or unit test is not proof of email delivery or
native deep-link behavior. No credentials or recovery tokens belong in logs.

Related: [auth feature map](../project-hub/generated/feature-auth.md),
[sign-in screen](../lib/features/auth/presentation/screens/sign_in_screen.dart),
[recovery screen](../lib/features/auth/presentation/screens/password_recovery_screen.dart),
[auth controller](../lib/core/auth/auth_controller.dart),
and [recovery widget tests](../test/password_recovery_screen_test.dart).
