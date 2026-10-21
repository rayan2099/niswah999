// Offline stand-in for https://deno.land/std@0.208.0/assert/mod.ts (the
// sandbox proxy blocks deno.land). Implements only what the repository's
// own Deno tests import, with std's semantics for those cases.
function equal(a: unknown, b: unknown): boolean {
  if (Object.is(a, b)) return true;
  if (a instanceof Date && b instanceof Date) return a.getTime() === b.getTime();
  if (typeof a !== 'object' || typeof b !== 'object' || a === null || b === null) return false;
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  const ka = Object.keys(a as object).filter((k) => (a as Record<string, unknown>)[k] !== undefined);
  const kb = Object.keys(b as object).filter((k) => (b as Record<string, unknown>)[k] !== undefined);
  if (ka.length !== kb.length) return false;
  return ka.every((k) => equal((a as Record<string, unknown>)[k], (b as Record<string, unknown>)[k]));
}
export function assertEquals(actual: unknown, expected: unknown, msg?: string): void {
  if (!equal(actual, expected)) {
    throw new Error(msg ?? `Values are not equal:\n  actual:   ${JSON.stringify(actual)}\n  expected: ${JSON.stringify(expected)}`);
  }
}
export function assertStrictEquals(actual: unknown, expected: unknown, msg?: string): void {
  if (!Object.is(actual, expected)) throw new Error(msg ?? `Not strictly equal: ${String(actual)} !== ${String(expected)}`);
}
export async function assertRejects(fn: () => Promise<unknown>, ..._rest: unknown[]): Promise<Error> {
  try {
    await fn();
  } catch (e) {
    return e as Error;
  }
  throw new Error('Expected function to reject.');
}
