# Agent workflow

1. Read [Home](Home.md), then the relevant [feature map](generated/Features.md) or [engineering map](generated/Engineering.md).
2. Search the original documents by feature, finding ID, or topic. Check dates and inspect current implementation; filename-matched tests are only hints.
3. Identify requirements, dependencies, unresolved questions, and evidence restrictions. Link a substantial open task using the work-item template.
4. Implement within the authorized task and run appropriate checks. Do not infer runtime readiness from documentation.
5. Update affected source docs and preserve meaningful rationale in a decision note. Record the exact verification and remaining limits.
6. Stage new source files, regenerate navigation, and run the freshness/link check. Deliver reviewable code/documentation changes together.

## Examples

- **Onboarding:** begin with [onboarding](generated/feature-onboarding.md), then [auth](generated/feature-auth.md) and [Madhhab resolution](generated/feature-madhhab_resolution.md). Read the owner checklist and current tests before assuming previous fixes are deployed.
- **Dr Niswah:** start with [AI assistant](generated/feature-ai_assistant.md), its backend entry point, shared retrieval/context code, and [knowledge policies](generated/Knowledge-and-Review.md).
- **Release:** follow [quality and release](generated/Quality-and-Release.md), the original runbooks, current Actions results, and actual environment verification.

`AGENTS.md` makes this discoverable by repository agents. It is guidance, not an enforcement mechanism for every external agent; CI enforces generated navigation freshness and local hub link integrity.
