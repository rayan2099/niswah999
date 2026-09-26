#!/usr/bin/env bash
# AUTH-08 needs a local GoTrue with email confirmations ENABLED. This
# temporarily flips supabase/config.toml, restarts the local stack (data
# volumes are kept), runs the AUTH-08 test, then ALWAYS restores the config
# and restarts the stack the way the rest of the suite expects it.
#   scripts/run_auth08_confirmations.sh <device-id>
set -uo pipefail
DEVICE="${1:?Usage: $0 <device-id>}"
cd "$(dirname "$0")/.."
python3 scripts/assert_test_backend.py --env-file .env || exit 3
CFG=supabase/config.toml
cp "$CFG" "$CFG.auth08.bak"
DUMMY="sbp_local_dummy_0000000000000000000000000000000000000000"
EXCL="analytics,vector,studio,imgproxy,edge-runtime,functions,realtime,storage,meta"
restore() {
  mv "$CFG.auth08.bak" "$CFG"
  SUPABASE_ACCESS_TOKEN="$DUMMY" supabase stop >/dev/null 2>&1
  for attempt in 1 2 3; do
    SUPABASE_ACCESS_TOKEN="$DUMMY" supabase start -x "$EXCL" >/dev/null 2>&1 && break
    SUPABASE_ACCESS_TOKEN="$DUMMY" supabase stop >/dev/null 2>&1
  done
  echo "config restored; local stack restarted with confirmations OFF"
}
trap restore EXIT
python3 - <<'PY'
import re
p="supabase/config.toml"; s=open(p).read()
s=re.sub(r"(\[auth\.email\][\s\S]*?enable_confirmations = )false", r"\1true", s, count=1)
open(p,"w").write(s)
PY
grep -n "enable_confirmations" "$CFG" | head -2
SUPABASE_ACCESS_TOKEN="$DUMMY" supabase stop >/dev/null 2>&1
for attempt in 1 2 3; do
  SUPABASE_ACCESS_TOKEN="$DUMMY" supabase start -x "$EXCL" >/dev/null 2>&1 && break
  echo "supabase start attempt $attempt failed; retrying"; SUPABASE_ACCESS_TOKEN="$DUMMY" supabase stop >/dev/null 2>&1
  [ "$attempt" = 3 ] && exit 4
done
rm -f build/integration_response_data.json
bash scripts/run_persona_local.sh "$DEVICE" integration_test/xAuth08_email_confirmation_test.dart
grep -o '"status":"[A-Z_]*"' build/integration_response_data.json 2>/dev/null
