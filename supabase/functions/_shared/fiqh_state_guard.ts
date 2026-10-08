// FD-1 (canonical menstrual-state authority) enforcement for fiqh-advisor-chat.
//
// The real, existing canonical engine for Haid/Tahara/Istihada
// classification is Dart-only: `CycleStatusEngine`/`MadhhabRuleEvaluator`
// (lib/features/cycle_tracking/domain/services/). It has no server-side
// counterpart and is not ported to TypeScript (unlike pregnancy/postpartum
// state, which is deliberately mirrored in pregnancy_status.ts) --
// reimplementing it here would create a second, independently-maintained
// copy of substantive Fiqh classification logic, which FD-1 explicitly does
// not authorize. Its output instead travels from the client as
// `clientFiqhState` (see ai_advisor_service.dart / chat_view_model.dart /
// client_fiqh_state_provider.dart) and is only ever explained here, never
// recomputed, overridden, or contradicted.
//
// This module is the server-side trust-boundary layer around that client
// value: (1) it accepts only the engine's own real enum values, so an
// arbitrary or adversarial string is never rendered into model context as
// if it were a genuine classification; (2) it deterministically detects
// whether a given question's answer depends on the asker's CURRENT state
// (as opposed to a general/definitional Fiqh question), so that an
// unresolved state can fail closed at the application layer -- before any
// model call -- rather than relying on the model to decide this itself.

/** The real `FiqhCycleState` enum values, exactly as `CycleStatusEngine`
 * produces them (lib/features/cycle_tracking/domain/services/
 * madhhab_rule_evaluator.dart: FiqhCycleState). Anything else received from
 * a client is not a genuine classification and must not be trusted as one. */
const VALID_FIQH_STATES = new Set([
  'insufficientHistory',
  'tahara',
  'haid',
  'needsAdvisory',
  'madhhabUnresolved',
]);

/** States the canonical engine itself reports as sufficiently resolved to
 * ground a state-dependent ruling. `needsAdvisory` is the engine's own
 * "cannot resolve with confidence, needs qualified guidance" signal, and
 * `madhhabUnresolved`/`insufficientHistory` are explicitly not a settled
 * classification -- all three are treated as unresolved here, matching the
 * engine's own semantics rather than inventing a new distinction. */
const RESOLVED_FIQH_STATES = new Set(['tahara', 'haid']);

/**
 * Validates a client-supplied `clientFiqhState` against the canonical
 * engine's real enum. Returns `null` for anything that is not one of the
 * five genuine values -- including garbage, injected strings, or an
 * adversarial client claiming a state the real engine never produced.
 * This is the only place `clientFiqhState` should be trusted from; nothing
 * downstream should read the raw request-body value directly.
 */
export function normalizeClientFiqhState(raw: unknown): string | null {
  return typeof raw === 'string' && VALID_FIQH_STATES.has(raw) ? raw : null;
}

/** Whether a normalized state (from `normalizeClientFiqhState`) is resolved
 * enough to ground a state-dependent Fiqh answer. */
export function isResolvedFiqhState(normalized: string | null): boolean {
  return normalized !== null && RESOLVED_FIQH_STATES.has(normalized);
}

// Deterministic, bilingual, keyword-based detection of whether a question's
// answer materially depends on the asker's CURRENT Haid/Tahara/Istihada
// state (e.g. "can I pray right now") as opposed to a general/definitional
// question (e.g. "what is the maximum duration of Haid") that does not.
// Imperfect by construction -- the same acknowledged tradeoff as
// dr_niswah_red_flags.ts's keyword scanner -- but deterministic, testable,
// and enforced at the application layer rather than left to model judgment.
const CURRENT_STATE_EN =
  /\b(right now|at the moment|currently|today|am i (?:currently |still )?(?:in|on)?\s*(?:haid|istihada|period|bleeding|pure|clean)|should i (?:pray|fast)|can i (?:pray|fast)|am i (?:allowed|able) to (?:pray|fast)|is it (?:ok|okay|permissible) (?:for me )?to (?:pray|fast)|figure out (?:my|the) state|calculate my (?:current )?state|based on these dates|here are my dates|decide (?:whether|if) i am (?:menstruating|bleeding|pure|clean))\b/i;

const CURRENT_STATE_AR =
  /(الآن|حاليًا|حالياً|اليوم|هل أنا|هل يجوز لي|هل يمكنني|احسبي حالتي|احسب حالتي|بناءً على هذه التواريخ|بناء على هذه التواريخ|قرري حالتي|حددي حالتي)/;

/**
 * True if the question's answer depends on knowing the asker's current
 * Haid/Tahara/Istihada state. Used only to decide whether an unresolved
 * canonical state must fail closed -- never to answer the question itself.
 */
export function isStateDependentQuestion(question: string): boolean {
  return CURRENT_STATE_EN.test(question) || CURRENT_STATE_AR.test(question);
}

/** Fail-closed response when a state-dependent question is asked but the
 * canonical engine could not resolve the asker's current state. Mirrors the
 * tone and structure of this function's other fixed fallback strings
 * (NO_MADHHAB_SELECTED_AR / NO_ELIGIBLE_KB_AR in index.ts). */
export const STATE_UNRESOLVED_AR =
  'لم يتمكن التطبيق من تحديد حالتك الفقهية الحالية (حيض/طهر) بثقة كافية للإجابة عن سؤال يعتمد مباشرة على ذلك، لذلك لن أفترض حالة معينة أو أصدر حكمًا آليًا بناءً عليها. يرجى التأكد من تسجيل بيانات دورتك في التطبيق، أو سؤال جهة إفتاء أو عالِمة مؤهلة عن حالتك الفعلية.';
