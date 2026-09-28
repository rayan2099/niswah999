// Runs the SERVER's real pregnancy engine (supabase/functions/_shared/
// pregnancy_status.ts — the code the AI Edge Functions use to build the
// pregnancy context) over the shared test vectors, so the app's Dart engine
// and the server engine are proven to agree. Requires Node >= 22.6
// (--experimental-strip-types); run:
//   node --experimental-strip-types scripts/pregnancy_status_parity.mjs
import { readFileSync } from 'node:fs';
import { getPregnancyStatus } from '../supabase/functions/_shared/pregnancy_status.ts';

const vectors = JSON.parse(
  readFileSync(new URL('../test/fixtures/pregnancy_status_vectors.json', import.meta.url)),
);
let failures = 0;
for (const v of vectors) {
  const status = getPregnancyStatus(v.row, new Date(v.today));
  const mismatched = Object.entries(v.expected).filter(([k, want]) => status[k] !== want);
  if (mismatched.length) {
    failures++;
    console.error(`FAIL ${v.name}: got ${JSON.stringify(status)}, expected ${JSON.stringify(v.expected)}`);
  }
}
console.log(`${vectors.length - failures}/${vectors.length} vectors match the server engine`);
process.exit(failures ? 1 : 0);
