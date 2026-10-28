# Physical sign-in UI findings — 2026-10-27

Observed directly over QuickTime USB preview on iPhone11, iOS15.6.1, TestFlight Niswah1.0.0(4). Backend unknown; no consent/auth/health data submitted.

- Switching Arabic to English updates the content, but Arabic remains highlighted. The const language-toggle subtree does not subscribe to the locale controller. A focused widget test reproduced the stale highlight on current main before remediation.
- English feature tiles truncate Pregnancy prediction, Women community and Dream interpretation on the physical screen at normal text scale.

Implemented: subscribe the toggle to locale changes and permit feature labels to wrap to their natural height. No claim of corrected TestFlight behavior.

Verification: 25 automated tests pass across the new English/Arabic highlight regression, 390px labels at normal and 200% text, existing sign-in RTL/auth-sheet tests and accessibility text scaling. Physical verification of these changes awaits a separately built/processed/installed artifact. Screenshots are retained in the local assessment output bundle, not committed with real-user data.

Related: [Auth feature map](../project-hub/generated/feature-auth.md). This note is evidence of limited UI checks, not clinical/scholarly validation or a public-launch GO decision.
