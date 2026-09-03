# Database & Data Integrity Audit — Reusable Master Template

> **Purpose:** A reusable production-readiness audit for verifying that an application's database layer preserves correctness, consistency, recoverability, and trustworthy state before launch.
>
> This template is designed for projects built manually or with AI coding agents. It is intentionally evidence-driven: **do not mark data integrity PASS because the schema exists, migrations run locally, or CRUD appears functional. Critical integrity guarantees must be proven through schema evidence and controlled execution whenever possible.**

---

# 0. Operating Rules

## 0.1 Audit objective

Determine whether the current database and persistence layer are safe for production by verifying:

- Schema structure matches actual application requirements.
- Primary keys, foreign keys, unique constraints, nullability, defaults, and checks are appropriate.
- Database relationships cannot silently drift into inconsistent state.
- Critical business invariants are enforced at the correct layer.
- Important writes are transactional where necessary.
- Duplicate records and duplicate side effects are prevented.
- Concurrent requests cannot create impossible states.
- Migrations are ordered, deterministic, reversible where practical, and safe to deploy.
- Destructive schema changes are identified before launch.
- Soft deletes, archives, retention rules, and cascades behave intentionally.
- Orphaned records are prevented or detectable.
- Data type choices are appropriate.
- Date/time, timezone, money, decimal, and identifier handling are consistent.
- Application models and actual database schema are aligned.
- Seed/demo/test data cannot accidentally pollute production.
- Database errors do not silently produce partial success.
- Backup/restore assumptions are explicit.
- Critical data changes can be rolled back or recovered.
- AI-generated migrations, models, and schema changes are internally consistent.

## 0.2 Non-goals

This audit does **not** replace:

- Security audit.
- Functional QA.
- Code quality audit.
- Dedicated performance/load testing.
- Privacy/legal review.
- Backup/disaster-recovery drill.
- Infrastructure/DevOps audit.

If an obvious issue from those disciplines is discovered, record it and cross-reference the appropriate specialist audit.

---

# 1. Mandatory Methodology

Use these stages in order:

| Stage | Name | What happens | Required output |
|---|---|---|---|
| 1 | **Discovery** | Understand schema, persistence architecture, migrations, models, relationships, critical entities, and write paths | Data architecture map |
| 2A | **Static Verification** | Compare schema, migrations, models, constraints, and business invariants | Integrity evidence matrix |
| 2B | **Controlled Validation** | Execute safe validation on an approved environment using synthetic data | PASS / FAIL / INCONCLUSIVE matrix |
| 3 | **Remediation Design** | Design root-cause fixes — **design only unless separately authorized** | Remediation plan |
| Final | **Production Readiness Report** | Consolidate evidence into a launch recommendation | GO / CONDITIONAL GO / NO-GO |

### Golden rule

**Application code is not a substitute for database integrity.**

If a critical invariant can be violated by concurrency, direct API use, background jobs, imports, retries, or another client, do not treat frontend validation as sufficient evidence.

---

# 2. Report Header

Use this header in every phase report:

| Field | Value |
|---|---|
| System | `{SYSTEM_NAME}` |
| Repository | `{REPOSITORY_NAME}` |
| Branch | `{BRANCH}` |
| Commit / Version | `{COMMIT_OR_VERSION}` |
| Database engine | `{POSTGRES / MYSQL / SQL SERVER / FIRESTORE / MONGODB / etc.}` |
| Database version | `{VERSION}` |
| ORM / Data layer | `{ORM / SDK / QUERY BUILDER}` |
| Phase | `{PHASE_NAME}` |
| Audit date | `{DATE}` |
| Environment | `{Local / Dev / Staging / Production}` |
| Environment status | `{🧪 Controlled / 🔴 Live production}` |
| Restrictions | `{WHAT_WAS_NOT_DONE}` |
| Report created | `{THIS_FILENAME}` |

---

# 3. Evidence and Confidence Key

| Symbol | Meaning |
|---|---|
| 🟥 **Confirmed by Runtime / Live Schema** | Proven by approved database inspection or controlled execution |
| 🟧 **Confirmed by Code / Migration** | Proven by explicit schema, model, migration, or persistence code |
| 🟨 **Likely** | Strong inference, but direct proof is incomplete |
| 🟦 **Requires Controlled Test** | Must be proven using controlled database behavior |
| ⬜ **Not Applicable / False Positive** | Does not apply or was proven irrelevant |

For every important finding, include:

- Finding ID.
- Severity.
- Table/collection/entity.
- Column/field/relationship.
- Migration or model reference.
- Evidence.
- Integrity risk.
- Confidence.
- Launch-blocker status.
- Proposed remediation category.

---

# 4. Severity Model

| Level | Classification | Data-integrity meaning | Launch treatment |
|---|---|---|---|
| **DI0** | Critical | Likely data loss, corruption, duplicate financial transaction, unrecoverable state, or cross-entity inconsistency in a critical workflow | **Mandatory NO-GO** |
| **DI1** | High | Core entities can become inconsistent, duplicated, orphaned, or invalid under realistic use | **Pre-launch blocker** |
| **DI2** | Medium | Integrity weakness exists but impact is bounded and recoverable with a safe workaround | Requires explicit acceptance |
| **DI3** | Low | Limited schema/data-quality issue with minor operational impact | Backlog acceptable |
| **DI4** | Observation | Improvement opportunity or design note | Backlog |

## 4.1 Severity factors

For DI0–DI2 findings, evaluate:

- Data criticality.
- Financial impact.
- Recoverability.
- Blast radius.
- Frequency.
- Concurrency exposure.
- Whether invalid state is detectable.
- Whether invalid state is automatically repairable.
- Whether production traffic increases likelihood.
- Whether the issue affects one record or many.
- Whether the issue impacts auditability or downstream systems.

---

# 5. Environment Warning

When using a non-production environment:

| Dimension | Evaluation |
|---|---|
| Technical severity | Based on the integrity flaw itself |
| Current actual impact | Based on current test/synthetic data |
| Production impact | State what happens if the same flaw reaches real users |
| Procedural classification | Unresolved DI0/DI1 issues are **Pre-Launch Blockers** |

Do not perform destructive production tests, real-data mutations, irreversible migrations, schema drops, mass deletes, or production repair operations without explicit authorization.

---

# PHASE 1 — DISCOVERY

# 6. Objective

Understand the database architecture before judging it.

### Mandatory restrictions

During discovery:

- Prefer read-only inspection.
- Do not run migrations.
- Do not alter schema.
- Do not seed production.
- Do not repair data.
- Do not drop tables/collections/indexes.
- Do not execute destructive scripts.
- Do not change constraints.
- Do not change RLS/policies.
- Do not run write tests against production.

---

# 7. Persistence Architecture Inventory

Document:

- Database engine(s).
- ORM/query builder/SDK.
- Migration framework.
- Schema source of truth.
- Model source of truth.
- Connection configuration.
- Read replicas.
- Caches.
- Object/file storage.
- Search engine.
- Queues/event stores.
- Analytics warehouses.
- External persistence providers.
- Background jobs that modify data.
- Scheduled jobs/cron.
- Import/export pipelines.

| Component | Technology | Purpose | Source of truth? | Writes data? | Criticality | Evidence |
|---|---|---|---|---|---|---|
| `{COMPONENT}` | `{TECH}` | `{PURPOSE}` | `{YES/NO}` | `{YES/NO}` | `{}` | `{PATH}` |

---

# 8. Entity Inventory

Create a complete inventory of important data entities.

| Entity ID | Table / Collection | Purpose | Primary key | Ownership | Criticality | Contains financial/personal data? |
|---|---|---|---|---|---|---|
| `ENT-001` | `{ENTITY}` | `{PURPOSE}` | `{PK}` | `{OWNER}` | `{Critical/High/Normal}` | `{YES/NO}` |

Include:

- Users/accounts.
- Profiles.
- Roles.
- Orders.
- Payments.
- Bookings.
- Subscriptions.
- Deliveries.
- Products.
- Inventory.
- Messages.
- Notifications.
- Files.
- Audit records.
- Settings.
- Integrations.
- Logs/events if persisted.
- Domain-specific core entities.

---

# 9. Relationship Inventory

Document all important relationships.

| Parent | Child | Relationship | FK/reference | Required? | Delete behavior | Update behavior | Evidence |
|---|---|---|---|---|---|---|---|
| `{PARENT}` | `{CHILD}` | `{1:1 / 1:N / N:N}` | `{FIELD}` | `{YES/NO}` | `{CASCADE/RESTRICT/SET NULL/etc.}` | `{}` | `{}` |

Flag:

- Relationships represented only by loose IDs with no enforcement.
- Nullable references that should be mandatory.
- Cascades that can delete too much.
- Missing cascades that create orphans.
- Cycles with dangerous cascading.
- Different relationship definitions across migrations/models.

---

# 10. Schema Source-of-Truth Inventory

Identify:

- Canonical schema file.
- Migration directory.
- ORM model definitions.
- Generated schema/types.
- API DTOs.
- Frontend models.
- Validation schemas.

| Concept | Sources | Canonical source | Drift risk | Notes |
|---|---|---|---|---|
| `{ENTITY/FIELD}` | `{PATHS}` | `{SOURCE}` | `{LOW/MED/HIGH}` | `{}` |

If no canonical source is identifiable, record a finding.

---

# 11. Migration Inventory

For every migration:

| Migration | Date/order | Purpose | Additive/destructive | Reversible? | Data migration? | Depends on | Status |
|---|---|---|---|---|---|---|---|
| `{FILE}` | `{ORDER}` | `{PURPOSE}` | `{TYPE}` | `{YES/NO/PARTIAL}` | `{YES/NO}` | `{PREVIOUS}` | `{}` |

Flag:

- Out-of-order migrations.
- Duplicate migrations.
- Conflicting migrations.
- Missing migrations for model changes.
- Schema changes made manually outside migration history.
- Destructive changes with no data migration.
- Migrations relying on local state.
- Non-deterministic migration logic.
- Migration scripts that call external APIs.
- Environment-specific schema changes.
- Seeds mixed into production migrations.

---

# 12. Critical Data Invariants

Define invariants that must always be true.

Use IDs:

- `INV-001`, `INV-002`, ...

Examples:

- One active subscription per user.
- One payment record per payment transaction.
- Order total cannot be negative.
- Booking cannot exceed available capacity.
- Delivered order must belong to an existing customer.
- Inventory cannot fall below allowed limit.
- User email must be unique if required.
- A cancelled entity cannot simultaneously be active.

| Invariant ID | Rule | Entities | Enforcement layer | DB-enforced? | Risk if violated |
|---|---|---|---|---|---|
| `INV-001` | `{RULE}` | `{ENTITIES}` | `{DB/API/APP}` | `{YES/NO/PARTIAL}` | `{IMPACT}` |

Critical invariants enforced only in UI should be flagged.

---

# 13. Identifier Strategy

Document:

- UUID.
- Auto-increment.
- ULID.
- Composite keys.
- External provider IDs.
- Natural keys.

Verify:

- Global uniqueness.
- Collision risk.
- Predictability implications if relevant.
- Cross-system compatibility.
- Identifier reuse.
- Mapping between internal/external IDs.
- Whether one concept uses multiple incompatible IDs.

---

# 14. Data Type Inventory

Inspect critical fields:

- Money.
- Decimal values.
- Currency.
- Dates.
- Times.
- Timestamps.
- Timezones.
- Distances.
- Coordinates.
- Quantities.
- Statuses.
- Booleans.
- JSON.
- IDs.
- Phone numbers.
- Email addresses.
- Large text.
- Binary/file references.

Flag inappropriate choices such as:

- floating-point money,
- ambiguous local timestamps,
- strings for numeric values without reason,
- unconstrained free-text statuses,
- inconsistent identifier types.

---

# 15. Nullability and Default Inventory

For important fields:

| Entity | Field | Nullable? | Default | Application assumption | Mismatch? |
|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{YES/NO}` |

Flag:

- Required application fields nullable in DB.
- Non-null fields with unsafe synthetic defaults.
- Defaults that hide missing data.
- `0`, empty string, or `false` used as unknown state.
- Timestamps defaulted incorrectly.
- Default roles/statuses that grant unintended behavior.

---

# 16. Unique Constraint Inventory

Verify uniqueness rules for:

- Emails.
- Usernames.
- External payment IDs.
- Idempotency keys.
- Order/reference numbers.
- Coupons.
- Slugs.
- Subscription relations.
- Join-table pairs.
- Booking/resource combinations.

| Entity | Unique rule | DB constraint exists? | App-only? | Concurrency safe? |
|---|---|---|---|---|
| `{}` | `{}` | `{YES/NO}` | `{YES/NO}` | `{YES/NO/UNKNOWN}` |

Application-only duplicate checks are not concurrency-safe by default.

---

# 17. Check Constraint / Domain Validation Inventory

Inspect whether important domain restrictions exist:

- Positive amounts.
- Valid percentages.
- Start < end.
- Quantity >= 0.
- Allowed status.
- Valid currency code.
- Valid geographic range.
- Valid date range.

Document what is:

- DB-enforced.
- API-enforced.
- UI-enforced.
- Not enforced.

---

# 18. Index Inventory

Document important indexes:

| Entity | Index | Columns | Unique? | Supports | Duplicate/redundant? |
|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{QUERY/CONSTRAINT}` | `{}` |

This is not a full performance audit, but missing indexes that materially affect critical write/read integrity or locking should be recorded.

---

# 19. Write-Path Inventory

For every critical mutation:

| Write ID | Action | Entry point | Tables/entities affected | Transaction? | External side effect? | Retry possible? |
|---|---|---|---|---|---|---|
| `WR-001` | `{ACTION}` | `{API/JOB}` | `{ENTITIES}` | `{YES/NO}` | `{PAYMENT/etc.}` | `{YES/NO}` |

Examples:

- Create account.
- Place order.
- Complete payment.
- Create booking.
- Cancel booking.
- Create subscription.
- Refund.
- Assign driver.
- Update inventory.
- Delete account.
- Import data.

---

# 20. Delete / Archive / Retention Model

Document:

- Hard delete.
- Soft delete.
- Archive.
- Deactivation.
- Tombstones.
- Retention window.
- Cascade behavior.
- Restoration capability.
- References to deleted entities.

Flag:

- Soft-deleted records still included unexpectedly.
- Unique constraints broken by soft delete strategy.
- Child records left permanently orphaned.
- Hard deletes on financially/audit-relevant data without intentional policy.
- Restored records colliding with new records.

---

# 21. Seed, Fixture, Demo, and Test Data Inventory

Identify:

- Seeds.
- Dev fixtures.
- Demo accounts.
- Mock records.
- Test factories.
- Bootstrap scripts.

Verify:

- Environment restrictions.
- Production safety.
- No default admin/test accounts.
- No real-looking fake customer data that could confuse operations.
- No fixed IDs that production code assumes exist.

---

# 22. Discovery Execution Log

### Fully reviewed
`{SCHEMA / MIGRATIONS / MODELS / REPOSITORIES}`

### Partially reviewed
`{AREAS}`

### Structurally scanned only
`{AREAS}`

### Could not inspect
`{AREAS + REASON}`

### Commands/actions performed
| Action | Purpose | Result |
|---|---|---|

### Actions deliberately avoided
| Action avoided | Reason |
|---|---|

---

# 23. Discovery Exit Gate

Phase 1 passes only when:

- [ ] Persistence architecture is mapped.
- [ ] Critical entities are identified.
- [ ] Critical relationships are mapped.
- [ ] Schema source of truth is identified.
- [ ] Migration history is understood.
- [ ] Critical invariants are identified.
- [ ] Critical write paths are mapped.
- [ ] Delete/retention behavior is understood.
- [ ] Seed/test data behavior is identified.
- [ ] Unknown/unreviewed areas are explicitly documented.

---

# PHASE 2A — STATIC VERIFICATION

# 24. Objective

Compare application assumptions against actual persistence design.

Use stable prefixes:

| Prefix | Category |
|---|---|
| `SCHEMA-xx` | Schema definition |
| `REL-xx` | Relationships/FKs |
| `UNIQ-xx` | Uniqueness/duplicates |
| `NULL-xx` | Nullability/defaults |
| `TYPE-xx` | Data types |
| `INV-xx` | Business invariants |
| `TX-xx` | Transactions/atomicity |
| `MIG-xx` | Migrations |
| `DEL-xx` | Delete/archive |
| `CONC-xx` | Concurrency/races |
| `IDEM-xx` | Idempotency |
| `MODEL-xx` | Model/schema drift |
| `SEED-xx` | Seed/test data |
| `TIME-xx` | Date/time/timezone |
| `MONEY-xx` | Money/decimal/currency |
| `ORPH-xx` | Orphan records |
| `INDEX-xx` | Integrity-relevant indexing |
| `IMPORT-xx` | Imports/bulk writes |
| `AUDIT-xx` | Auditability/history |

---

# 25. Primary Key Audit

Verify:

- Every relational entity has a stable primary key where appropriate.
- Key type is consistent.
- Keys are immutable.
- Composite keys are intentional.
- External IDs are not accidentally used as internal PKs when unsafe.
- No duplicate key-generation logic exists.

---

# 26. Foreign Key / Reference Audit

Verify:

- Required relationships are enforced.
- Reference types match.
- Cascades are intentional.
- Updates cannot create dangling references.
- Deletions cannot silently break required children.
- Document databases validate references at application or service layer where DB-level FK is unavailable.

Flag any critical entity where referential integrity relies entirely on UI behavior.

---

# 27. Unique Constraint Audit

For every critical uniqueness rule:

1. Identify intended uniqueness.
2. Check whether DB-level enforcement exists.
3. Check whether soft deletes affect uniqueness.
4. Check whether concurrent requests can bypass application-only checks.
5. Check whether external IDs need uniqueness.

High-impact duplicate candidates include:

- Payment transaction IDs.
- Refund IDs.
- Active subscriptions.
- Booking slots.
- Coupon redemption.
- User identity.
- Order numbers.
- Webhook event IDs.

---

# 28. Nullability / Default Audit

Inspect critical fields for:

- Unsafe null.
- Unsafe default.
- Missing default.
- Application/DB mismatch.
- Serialization mismatch.
- Existing old rows incompatible with new non-null assumptions.

---

# 29. Data Type Audit

## Money

Preferred considerations:

- Integer minor units or exact decimal type.
- Explicit currency.
- Defined rounding behavior.

Flag:

- Binary floating-point for financial amounts.
- Currency-less amount fields where multiple currencies are possible.
- Frontend/backend decimal mismatch.

## Date/time

Verify:

- UTC storage where appropriate.
- Timezone conversion ownership.
- Local business timezone rules.
- Daylight-saving behavior where relevant.
- Start/end consistency.
- Expiration comparisons.
- Database/client timezone mismatch.

## Status fields

Verify:

- Allowed values.
- Enum consistency.
- Legacy values.
- Unknown states.
- Case sensitivity.

---

# 30. Invariant Enforcement Audit

For each `INV-xxx`:

| Invariant | DB enforcement | Backend enforcement | Frontend enforcement | Concurrency-safe? | Assessment |
|---|---|---|---|---|---|
| `{ID}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL}` |

Important question:

**Can the invariant be violated by two valid requests executing simultaneously?**

If yes, application-level pre-checks may be insufficient.

---

# 31. Transaction Audit

For every critical multi-step write:

Determine whether all-or-nothing behavior is required.

Examples:

- Order + order items.
- Payment + order status.
- Booking + capacity decrement.
- Refund + payment ledger.
- Subscription + entitlement.
- Driver assignment + order status.
- Inventory decrement + order creation.

| Write ID | Steps | Transaction required? | Transaction exists? | Failure midpoint risk | Finding |
|---|---|---|---|---|---|

Flag:

- Partial commits.
- Side effects before commit.
- External API calls inside long transactions without clear strategy.
- Commit followed by critical failure with no compensation.
- Transactions spanning unsupported systems with no saga/compensation design.

---

# 32. Idempotency Audit

For operations that can be retried:

- Payment webhook.
- Refund webhook.
- Order creation.
- Booking creation.
- Subscription event.
- Email/job dispatch if duplicate matters.
- Import.
- Background task.
- External callback.

Verify:

- Stable idempotency key.
- Unique enforcement.
- Duplicate-event detection.
- Result reuse.
- Safe retries.
- Expiration policy where applicable.

---

# 33. Concurrency Audit

Identify race-prone resources:

- Capacity.
- Inventory.
- Last available slot.
- Single assignment.
- Coupon limits.
- Unique usernames/emails.
- Balance/credits.
- Counters.
- Queue positions.
- Rate/usage quotas.

Inspect:

- Atomic update.
- Locking.
- Optimistic concurrency/version column.
- Conditional update.
- Unique constraint.
- Transaction isolation.
- Compare-and-swap.
- Database-native atomic operations.

Flag read-then-write logic with no concurrency protection.

---

# 34. Orphan Prevention Audit

Inspect whether:

- Parent deletion leaves children.
- Import scripts bypass relationships.
- Background jobs create references before parent commit.
- Soft-delete behavior leaves active children pointing to inactive parent.
- External IDs refer to deleted entities.

Document orphan detection strategy where relevant.

---

# 35. Soft Delete Audit

Verify:

- Global query filtering.
- Admin visibility.
- Restore behavior.
- Unique constraint behavior.
- Cascading soft delete.
- Child entity semantics.
- Historical reports.
- Re-creation behavior.
- Background jobs ignoring deleted rows.

---

# 36. Migration Safety Audit

For each significant migration, inspect:

- Order dependency.
- Re-runnability.
- Transactional behavior.
- Locking risk.
- Table rewrite risk.
- Data backfill.
- Default behavior.
- Null-to-not-null sequence.
- Rename compatibility.
- Column drop timing.
- Index creation strategy.
- Old-client compatibility.
- Rollback.

Classify migration:

- Safe additive.
- Requires staged rollout.
- Destructive.
- Data-transforming.
- High-lock risk.
- Unknown.

---

# 37. Expand-and-Contract Audit

For breaking schema changes, verify staged compatibility where needed:

1. Add new schema.
2. Deploy code supporting old + new.
3. Backfill.
4. Switch reads/writes.
5. Verify.
6. Remove old schema later.

Flag one-step destructive migration where zero-downtime or multi-client compatibility is required.

---

# 38. Model / Schema Drift Audit

Compare:

- ORM model vs migration.
- Backend DTO vs ORM.
- Frontend model vs API.
- Generated type vs schema.
- Validation schema vs DB nullability.
- Enum definitions across layers.

Flag:

- Field renamed in one layer only.
- Type mismatch.
- Nullable mismatch.
- Default mismatch.
- Enum mismatch.
- Relation name mismatch.
- Generated code stale.

---

# 39. Import / Bulk Write Audit

Inspect:

- CSV imports.
- Admin bulk tools.
- ETL.
- Data migration scripts.
- Batch jobs.

Verify:

- Validation.
- Transaction/batch behavior.
- Duplicate detection.
- Partial failure reporting.
- Retry behavior.
- Auditability.
- Cleanup.
- Referential integrity.

Bulk paths often bypass normal application safeguards.

---

# 40. Auditability / History Audit

For critical domains, determine whether the system can answer:

- Who changed it?
- What changed?
- When?
- From what to what?
- Why?
- Which external transaction/event caused it?

Do not require full event sourcing unless the domain needs it.

Flag missing history where financial, legal, operational, or dispute-resolution needs make it critical.

---

# 41. AI-Agent-Specific Database Audit

Mandatory when AI agents were used.

Actively search for:

## 41.1 Duplicate migrations

- Same column added twice.
- Same table created by competing migrations.
- Old migration left after schema regeneration.
- Conflicting indexes.

## 41.2 Model drift

- Agent edits model but forgets migration.
- Agent edits migration but forgets model.
- Generated types not refreshed.
- Frontend types still use previous schema.

## 41.3 Unsafe “quick fixes”

- Making column nullable instead of fixing write logic.
- Adding default `0`, `""`, or `false` to satisfy migration.
- Removing FK to stop an error.
- Removing unique constraint because inserts fail.
- Catching DB errors and returning success.
- Adding broad cascade delete to avoid cleanup logic.

## 41.4 Parallel sources of truth

- SQL schema + ORM schema disagree.
- Supabase schema + local migrations disagree.
- Firestore document shape differs across features.
- Different agents create different field names for same concept.

## 41.5 Test schema pollution

- Test-only columns.
- Demo records expected by production logic.
- Seeded admin account.
- Local dev IDs hardcoded into application code.

## 41.6 Incomplete refactors

- New column introduced while old code still writes old column.
- Read path migrated, write path not migrated.
- New relationship exists while old denormalized field remains authoritative.
- Migration exists but backfill missing.

## 41.7 Hallucinated database behavior

- ORM option does not exist.
- Constraint syntax invalid for actual DB engine.
- Transaction semantics misunderstood.
- Firestore atomicity assumed across unsupported scope.
- Client-side transaction assumed equivalent to server-side constraint.

---

# 42. Static Verification Matrix

| Check ID | Category | Scope | Expected condition | Evidence | Result |
|---|---|---|---|---|---|
| `{ID}` | `{CATEGORY}` | `{ENTITY/MIGRATION}` | `{EXPECTED}` | `{PATH}` | `{PASS/FAIL/INCONCLUSIVE}` |

Allowed results:

- PASS
- FAIL
- INCONCLUSIVE
- NOT APPLICABLE

---

# 43. Static Verification Exit Gate

Phase 2A passes only when:

- [ ] PK strategy reviewed.
- [ ] Critical relationships reviewed.
- [ ] Critical uniqueness reviewed.
- [ ] Nullability/defaults reviewed.
- [ ] Money/time/status types reviewed.
- [ ] Critical invariants reviewed.
- [ ] Critical transaction boundaries reviewed.
- [ ] Idempotency reviewed.
- [ ] Concurrency reviewed.
- [ ] Migration safety reviewed.
- [ ] Model/schema drift reviewed.
- [ ] Delete/archive behavior reviewed.
- [ ] AI-generated schema risks reviewed.
- [ ] All DI0/DI1 candidates have evidence.

---

# PHASE 2B — CONTROLLED VALIDATION

# 44. Objective

Prove critical integrity behavior on an approved environment using synthetic data.

### Mandatory restrictions

- Prefer isolated local/test/staging DB.
- Never mutate production data without explicit authorization.
- Clearly prefix synthetic records.
- Never use real card/payment credentials.
- Never expose secrets.
- Document cleanup.
- Snapshot/backup test data if needed before destructive test cases.
- Avoid uncontrolled load.

---

# 45. Test Data Convention

Use:

`QA_{PROJECT}_{DATE}_{CASE}`

Document:

| Data set | Purpose | Created by | Cleanup | Status |
|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 46. Integrity Test Categories

| Prefix | Category |
|---|---|
| `DB-PK-xx` | Primary key |
| `DB-FK-xx` | Relationship / orphan |
| `DB-UQ-xx` | Uniqueness |
| `DB-NULL-xx` | Nullability |
| `DB-CHK-xx` | Check/domain constraint |
| `DB-TX-xx` | Transaction |
| `DB-IDEM-xx` | Idempotency |
| `DB-CONC-xx` | Concurrency |
| `DB-DEL-xx` | Delete/archive |
| `DB-MIG-xx` | Migration |
| `DB-TIME-xx` | Time/date |
| `DB-MONEY-xx` | Money |
| `DB-MODEL-xx` | Schema/model consistency |
| `DB-IMPORT-xx` | Import/bulk |
| `DB-RESTORE-xx` | Recovery validation |

---

# 47. Controlled Test Matrix

| Test ID | Invariant / Risk | Preconditions | Action | Expected DB result | Actual DB result | Evidence | Result |
|---|---|---|---|---|---|---|---|
| `{ID}` | `{REF}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{PASS/FAIL/INCONCLUSIVE}` |

---

# 48. Duplicate Test

For every critical unique entity:

1. Create valid first record.
2. Attempt exact duplicate.
3. Attempt semantically duplicate variant.
4. Attempt concurrent duplicates where safe.
5. Verify only valid state persists.
6. Verify application handles rejection correctly.

---

# 49. Transaction Failure Test

For each critical multi-step mutation:

Where safely controllable, simulate failure after an intermediate step.

Verify:

- No partial inconsistent state remains.
- Compensation occurs if cross-system transaction cannot be atomic.
- Retry is safe.
- User-facing state matches persisted state.

---

# 50. Concurrency Test

Where safe, submit simultaneous operations against same resource.

Examples:

- Last booking slot.
- Last inventory unit.
- Same coupon limit.
- Same username/email.
- Same payment event.
- Same driver assignment.

Expected result must be explicit before execution.

---

# 51. Idempotency Test

Execute same logical request/event twice.

Verify:

- One logical effect.
- Same result or safe duplicate response.
- No duplicate payment/order/refund/subscription.
- Duplicate event is detectable.

---

# 52. Delete / Restore Test

Where applicable:

- Delete/soft-delete parent.
- Inspect children.
- Verify query visibility.
- Verify restore.
- Verify uniqueness.
- Verify history.
- Verify background jobs.

---

# 53. Migration Validation

In a disposable/test environment:

1. Start from known prior schema.
2. Apply migration sequence.
3. Verify schema.
4. Verify data backfill.
5. Run app against migrated DB.
6. Validate critical queries/writes.
7. Test rollback where supported/required.

Never claim migration safety based only on reading the migration file when runtime validation is necessary.

---

# 54. Schema Diff Validation

Where tooling permits:

Compare:

- Expected schema.
- Actual staging schema.
- Migration-derived schema.
- ORM-generated schema.

Record drift.

---

# 55. Controlled Validation Summary

| Metric | Count |
|---|---:|
| Tests planned | `{}` |
| Executed | `{}` |
| PASS | `{}` |
| FAIL | `{}` |
| INCONCLUSIVE | `{}` |
| BLOCKED | `{}` |
| DI0 findings | `{}` |
| DI1 findings | `{}` |
| DI2 findings | `{}` |

---

# 56. Controlled Validation Exit Gate

Phase 2B passes only when:

- [ ] All critical invariants were executed or explicitly blocked.
- [ ] Critical uniqueness was runtime-tested.
- [ ] Critical transaction behavior was tested where applicable.
- [ ] Critical concurrency was tested where applicable.
- [ ] Critical idempotency was tested where applicable.
- [ ] Migration path was validated where feasible.
- [ ] Test data cleanup is documented.
- [ ] Every FAIL has a finding ID.
- [ ] No critical result is inferred from application UI alone.

---

# 57. Finding Register

| Finding ID | Category | Severity | Entity | Summary | Evidence | Root-cause status | Launch blocker? | Status |
|---|---|---|---|---|---|---|---|---|
| `DI-001` | `{CATEGORY}` | `{DI0-DI4}` | `{ENTITY}` | `{SUMMARY}` | `{EVIDENCE}` | `{UNKNOWN/LIKELY/CONFIRMED}` | `{YES/NO}` | `OPEN` |

---

# PHASE 3 — REMEDIATION DESIGN

# 58. Mandatory Notice

> ⚠️ **This remediation plan is proposed and not yet implemented.** It requires technical review and a separate implementation decision. Nothing below should be described as fixed until schema/code changes are completed and controlled validation is rerun.

---

# 59. Objective

Design fixes that restore data correctness at the appropriate layer.

Prefer:

- database constraints,
- transactions,
- idempotency,
- atomic operations,
- safe migrations,
- explicit domain rules,
- one schema source of truth.

Do not fix integrity problems only in the frontend.

---

# 60. Root-Cause Map

| Finding | Symptom | Root cause | Confidence | Related findings | Remediation phase |
|---|---|---|---|---|---|
| `DI-001` | `{}` | `{}` | `{}` | `{}` | `R1` |

---

# 61. Remediation Principles

| Principle | Application |
|---|---|
| Database protects critical invariants | Do not rely solely on UI checks |
| Atomicity where required | Critical multi-write operations commit or fail together |
| Idempotent external events | Duplicate callbacks produce one logical effect |
| Constraint before cleanup | Prevent recurrence after repairing bad data |
| Expand before contract | Avoid destructive one-step migrations |
| Backfill before NOT NULL | Make existing rows compatible first |
| One schema source of truth | Eliminate drift |
| Reversible rollout | Use rollback/compatibility where practical |
| Observable migrations | Record progress and failure |
| Retest after repair | Schema change alone is not closure |

---

# 62. Data Repair Plan

If invalid historical data exists, separate:

1. **Prevention fix**
2. **Detection query**
3. **Repair script**
4. **Dry run**
5. **Backup/snapshot**
6. **Controlled execution**
7. **Post-repair validation**
8. **Audit record**

Never mix destructive repair with schema migration without explicit design.

---

# 63. Remediation Phase Table

| # | Action | Findings closed | Schema changes | Code changes | Data repair | Risk | Rollback | Retest |
|---|---|---|---|---|---|---|---|---|
| `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` | `{}` |

---

# 64. Migration Rollout Requirements

For risky schema changes, document:

- Deployment order.
- Compatibility window.
- Backfill.
- Locking expectations.
- Rollback.
- Old-client behavior.
- New-client behavior.
- Feature flag if needed.
- Monitoring.
- Success criteria.

---

# 65. Remediation Exit Gate

Implementation-ready only when:

- [ ] Root cause is identified.
- [ ] Constraint/transaction strategy is defined.
- [ ] Existing bad data impact is assessed.
- [ ] Backfill/repair plan exists if necessary.
- [ ] Migration order is defined.
- [ ] Rollback exists where needed.
- [ ] Cross-version compatibility is understood.
- [ ] Retest cases are defined.
- [ ] Functional/API impacts are cross-referenced.

---

# FINAL — DATABASE & DATA INTEGRITY PRODUCTION READINESS REPORT

# 66. Objective

Produce one release decision for the exact audited version/schema.

---

# 67. Executive Summary

### System
`{SYSTEM_NAME}`

### Version / Commit
`{VERSION}`

### Database
`{ENGINE + VERSION}`

### Schema/migration baseline
`{MIGRATION / SCHEMA VERSION}`

### Open findings
- DI0: `{COUNT}`
- DI1: `{COUNT}`
- DI2: `{COUNT}`
- DI3: `{COUNT}`

### Critical integrity tests
`{PASS}/{EXECUTED}`

### Critical unknowns
`{COUNT + SUMMARY}`

### Final recommendation
`{🟢 GO / 🟡 CONDITIONAL GO / 🔴 NO-GO}`

---

# 68. Launch Decision Rules

## 🟢 GO

Use **GO** only when:

- Zero open DI0.
- Zero open DI1.
- Critical relationships are protected.
- Critical uniqueness rules are concurrency-safe.
- Critical financial/data writes are atomic or safely compensated.
- Critical retries/webhooks are idempotent where applicable.
- Critical concurrency scenarios are safe.
- Migration path is validated.
- No critical model/schema drift remains.
- No production-path test/demo data dependency exists.
- No unresolved orphan/data-corruption risk remains.
- Critical date/time and money handling are correct.
- No critical unknown remains.

## 🟡 CONDITIONAL GO

Use only when:

- Zero DI0.
- Zero launch-blocking DI1.
- Remaining issues are bounded and recoverable.
- No core financial/data invariant is uncertain.
- No critical migration risk remains.
- Release owner explicitly accepts residual DI2 risk.

## 🔴 NO-GO

Use if any of the following is true:

- Any DI0 remains open.
- Any DI1 can corrupt core data.
- Duplicate financial/business records can occur.
- Core multi-step writes can partially commit.
- Critical concurrency can produce impossible state.
- Critical migration path is unverified or destructive without safe rollout.
- Core models and DB schema materially disagree.
- Orphaning/data loss is realistic.
- Critical write behavior is unknown.
- Production relies on demo/test/seed assumptions.

---

# 69. Launch Gate Table

| Gate | Requirement | Evidence | Status |
|---|---|---|---|
| `LG-DI-01` | Zero open DI0 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-DI-02` | Zero launch-blocking DI1 | `{REGISTER}` | `{PASS/FAIL}` |
| `LG-DI-03` | Critical FKs/references safe | `{TESTS}` | `{PASS/FAIL}` |
| `LG-DI-04` | Critical uniqueness concurrency-safe | `{TESTS}` | `{PASS/FAIL}` |
| `LG-DI-05` | Critical transactions safe | `{TESTS}` | `{PASS/FAIL}` |
| `LG-DI-06` | Critical idempotency verified | `{TESTS}` | `{PASS/FAIL}` |
| `LG-DI-07` | Critical concurrency verified | `{TESTS}` | `{PASS/FAIL}` |
| `LG-DI-08` | Migration path validated | `{TESTS}` | `{PASS/FAIL}` |
| `LG-DI-09` | Model/schema alignment verified | `{EVIDENCE}` | `{PASS/FAIL}` |
| `LG-DI-10` | No critical orphan/data-loss path | `{EVIDENCE}` | `{PASS/FAIL}` |
| `LG-DI-11` | Money/time handling verified | `{TESTS}` | `{PASS/FAIL}` |
| `LG-DI-12` | No critical unknowns | `{OPEN ITEMS}` | `{PASS/FAIL}` |

Any mandatory FAIL prevents GO.

---

# 70. Residual Risk Register

| Risk ID | Finding | Severity | Probability | Production impact | Mitigation | Owner | Required before launch? |
|---|---|---|---|---|---|---|---|
| `RISK-DI-001` | `{REF}` | `{DI}` | `{LOW/MED/HIGH}` | `{}` | `{}` | `{}` | `{YES/NO}` |

---

# 71. Out-of-Scope / Not Verified

Explicitly list:

- Production DB not accessible.
- Schema introspection unavailable.
- Certain collections/tables unavailable.
- Historical data not sampled.
- Backup restore not executed.
- Replication not assessed.
- External data store not accessible.
- Closed-source integration persistence not inspectable.
- Certain migrations not executable.
- Concurrency test blocked.
- Production-only cron/jobs not tested.
- Anything intentionally excluded.

Do not convert lack of access into PASS or FAIL.

---

# 72. Final One-Sentence Recommendation

### GO example

> Database & Data Integrity recommendation: **GO for production** for `{VERSION}` because all mandatory data-integrity launch gates passed and no unresolved critical corruption, duplication, migration, or consistency risk remains.

### CONDITIONAL GO example

> Database & Data Integrity recommendation: **CONDITIONAL GO** for `{VERSION}`, subject to explicit acceptance of the documented DI2 residual risks; all critical integrity guarantees are verified.

### NO-GO example

> Database & Data Integrity recommendation: **NO-GO** for `{VERSION}` until findings `{DI-xxx...}` are remediated and the associated integrity, migration, concurrency, and regression tests pass.

---

# 73. Required Deliverables

A complete audit should produce:

1. `01_DATABASE_DISCOVERY_REPORT.md`
2. `02_DATA_INTEGRITY_STATIC_VERIFICATION_REPORT.md`
3. `03_DATA_INTEGRITY_TEST_EXECUTION_REPORT.md`
4. `04_DATABASE_REMEDIATION_PLAN.md`
5. `05_DATABASE_PRODUCTION_READINESS_REPORT.md`

Optional supporting files:

- `SCHEMA_MAP.md`
- `ENTITY_RELATIONSHIP_MAP.md`
- `MIGRATION_INVENTORY.md`
- `DATA_INVARIANTS.md`
- `DATA_INTEGRITY_FINDINGS.csv`
- `ORPHAN_DETECTION_QUERIES.md`
- `DATA_REPAIR_PLAN.md`

---

# 74. Instructions to the AI Auditor

When this template is supplied to an AI coding agent:

1. Read this template completely before starting.
2. Do not run migrations during Discovery.
3. Do not modify schema during Verification.
4. Do not repair data while auditing.
5. Do not use production writes without explicit authorization.
6. Do not expose credentials, connection strings, or secrets.
7. Cite exact schema/model/migration paths.
8. Record actual database engine/version where known.
9. Do not assume ORM models equal live schema.
10. Do not assume frontend validation protects database integrity.
11. Do not assume a duplicate pre-check is concurrency-safe.
12. Do not assume multi-step writes are atomic.
13. Do not assume external callbacks arrive once.
14. Do not assume migration order is safe because files are timestamped.
15. Do not remove FKs/constraints merely to make tests pass.
16. Do not make fields nullable merely to bypass migration failures.
17. Do not add unsafe defaults to silence schema errors.
18. Do not invent expected business invariants.
19. Separate schema defects from product-spec ambiguity.
20. Inspect AI-generated migrations for duplication and drift.
21. Compare models, migrations, generated types, and API schemas.
22. Preserve stable finding IDs.
23. Cross-reference functional/API/security issues where relevant.
24. Retest before marking a finding Verified Closed.
25. End with exactly one recommendation: **GO, CONDITIONAL GO, or NO-GO**.

---

# 75. Completion Standard

This audit is complete only when an independent reviewer could answer:

- What databases and persistence systems exist?
- What are the critical entities?
- How are entities related?
- What invariants must always hold?
- Which invariants are actually enforced?
- Can duplicates occur?
- Can orphaned records occur?
- Are critical writes transactional?
- Are retries idempotent?
- Can concurrency create impossible state?
- Are money and timestamps represented correctly?
- Are migrations safe?
- Are models and schema aligned?
- Is soft-delete behavior intentional?
- Is test/demo data isolated?
- What was actually runtime-tested?
- What remains unknown?
- What remediation is proposed versus verified?
- Can this exact schema/version preserve trustworthy data in production?

If those questions cannot be answered from the audit outputs, the audit is not complete.
