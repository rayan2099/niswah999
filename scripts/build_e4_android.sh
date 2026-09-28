#!/usr/bin/env bash
# Builds the Android sideload build for the E4 (physical-device) pass, for an
# EXACT commit, from a clean worktree — so the file corresponds to committed
# code, not to whatever is in the working tree.
#
#   scripts/build_e4_android.sh <sha> [env-file]
#
# * A PROFILE build (AOT, release-like performance), debug-signed: installable
#   by sideloading, NOT publishable to a store.
# * Built WITHOUT --dart-define=ACCEPTANCE_TEST (that switch exists to refuse
#   real backends; an E4 pass uses the backend the founder chooses).
# * Built WITH GIT_SHA and ENABLE_DIAGNOSTICS_SCREEN so the running app shows
#   "SHA:<12> ENV:<env> BACKEND:<host>" and a tester can confirm the build.
# * Refuses an env file that points at a loopback / emulator-alias backend
#   (that build could not work on a phone). Keys are never printed.
# Writes dist/niswah-e4-<sha12>.apk and dist/E4_BUILD_MANIFEST.md (dist/ is
# gitignored).
set -euo pipefail
cd "$(dirname "$0")/.."
SHA="$(git rev-parse "${1:?usage: $0 <sha> [env-file]}")"
SHORT="${SHA:0:12}"
ENV_FILE="${2:-}"
if [ -z "$ENV_FILE" ]; then
  if [ -f .env.real.backup ]; then ENV_FILE=.env.real.backup; else ENV_FILE=.env; fi
fi
[ -f "$ENV_FILE" ] || { echo "no env file at $ENV_FILE" >&2; exit 2; }

HOST="$(python3 - "$ENV_FILE" <<'PY'
import re, sys
url = ""
for line in open(sys.argv[1]):
    if line.startswith("SUPABASE_URL="):
        url = line.split("=", 1)[1].strip()
m = re.match(r"https?://([^/:@]+)", url)
print(m.group(1) if m else "")
PY
)"
APP_ENV="$(grep '^APP_ENV=' "$ENV_FILE" | head -1 | cut -d= -f2- || true)"
case "$HOST" in
  ""|localhost|127.*|10.0.2.2|0.0.0.0) echo "refusing: $ENV_FILE targets '$HOST', which a phone cannot reach" >&2; exit 3 ;;
esac

WT="$(mktemp -d)/niswah-e4"
git worktree add --detach "$WT" "$SHA" >/dev/null
trap 'git worktree remove --force "$WT" >/dev/null 2>&1 || true' EXIT
cp "$ENV_FILE" "$WT/.env"
( cd "$WT" && flutter pub get >/dev/null && \
  flutter build apk --profile \
    --dart-define=GIT_SHA="$SHA" \
    --dart-define=ENABLE_DIAGNOSTICS_SCREEN=true )

mkdir -p dist
OUT="dist/niswah-e4-$SHORT.apk"
cp "$WT/build/app/outputs/flutter-apk/app-profile.apk" "$OUT"
SUM="$(shasum -a 256 "$OUT" | cut -d' ' -f1)"
SIZE="$(du -h "$OUT" | cut -f1)"
cat > dist/E4_BUILD_MANIFEST.md <<MANIFEST
# E4 build manifest

| | |
|---|---|
| Git SHA (full) | \`$SHA\` |
| On-screen banner shows | \`SHA:$SHORT  ENV:${APP_ENV:-unset}  BACKEND:$HOST\` |
| File | \`$OUT\` ($SIZE) |
| SHA-256 | \`$SUM\` |
| Build type | Android **profile** (AOT), debug-signed — sideload only |
| Built | $(date -u +%Y-%m-%dT%H:%M:%SZ) from a clean worktree at that SHA |
| Acceptance kill switch | not armed (no ACCEPTANCE_TEST define) — this build talks to \`$HOST\` |

Install: \`adb install -r $OUT\` (or copy to the phone). Before testing, confirm
the banner's SHA equals the one above. E4 is **NOT PASSED** until every row of
\`E4_PHYSICAL_DEVICE_CHECKLIST.md\` has been physically executed.
MANIFEST
echo "built $OUT  sha256=$SUM"
