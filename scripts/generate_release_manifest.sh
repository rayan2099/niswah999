#!/usr/bin/env bash
# Generates a release manifest (release-manifest.template.json's schema) for
# a real build artifact. RD-009 (Production Rollback / Rapid Recovery
# Capability wave, 2026-09-06). Never prints or embeds secrets.
#
# Usage: scripts/generate_release_manifest.sh <artifact-path> <environment> [build-number]
#   artifact-path : path to a built .apk or .aab
#   environment   : production | staging | development (the APP_ENV used for this build)
#   build-number  : optional; defaults to reading pubspec.yaml's version field
#
# Edge Function versions and DB migration state are NOT auto-filled — no
# automated correlation exists between a client build and those two facts
# (see docs/release-manifest-template.md). The script leaves them blank
# with a reminder; fill them manually from:
#   supabase functions list --project-ref <ref>
#   supabase migration list --linked

set -euo pipefail

ARTIFACT_PATH="${1:?Usage: $0 <artifact-path> <environment> [build-number]}"
ENVIRONMENT="${2:?Usage: $0 <artifact-path> <environment> [build-number]}"

if [ ! -f "$ARTIFACT_PATH" ]; then
  echo "error: artifact not found at $ARTIFACT_PATH" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

GIT_SHA="$(git rev-parse HEAD)"
GIT_REF="$(git rev-parse --abbrev-ref HEAD)"

VERSION_LINE="$(grep '^version:' pubspec.yaml)"
# BSD sed (macOS default) has no \s — use a literal space/tab class instead.
SEMANTIC_VERSION="$(echo "$VERSION_LINE" | sed -E 's/version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+.*/\1/')"
PUBSPEC_BUILD_NUMBER="$(echo "$VERSION_LINE" | sed -E 's/.*\+([0-9]+).*/\1/')"
BUILD_NUMBER="${3:-$PUBSPEC_BUILD_NUMBER}"

FLUTTER_VERSION="$(flutter --version 2>/dev/null | head -1 | awk '{print $2}')"
BUILD_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

ARTIFACT_TYPE="apk"
case "$ARTIFACT_PATH" in
  *.aab) ARTIFACT_TYPE="aab" ;;
  *.apk) ARTIFACT_TYPE="apk" ;;
esac

ARTIFACT_SHA256="$(shasum -a 256 "$ARTIFACT_PATH" | awk '{print $1}')"
ARTIFACT_SIZE="$(stat -f%z "$ARTIFACT_PATH" 2>/dev/null || stat -c%s "$ARTIFACT_PATH")"

CERT_CN=""
CERT_SHA256=""
APKSIGNER="$(find "$HOME/Library/Android/sdk/build-tools" -name apksigner 2>/dev/null | sort -V | tail -1)"
JBR_HOME="$(find /Applications -maxdepth 4 -iname jbr -type d 2>/dev/null | head -1)"
if [ -n "$APKSIGNER" ] && [ -n "$JBR_HOME" ] && [ "$ARTIFACT_TYPE" = "apk" ]; then
  VERIFY_OUT="$(JAVA_HOME="$JBR_HOME/Contents/Home" "$APKSIGNER" verify --print-certs "$ARTIFACT_PATH" 2>/dev/null || true)"
  CERT_CN="$(echo "$VERIFY_OUT" | grep 'certificate DN' | head -1 | sed -E 's/.*DN: (.*)/\1/')"
  CERT_SHA256="$(echo "$VERIFY_OUT" | grep 'SHA-256 digest' | head -1 | awk '{print $NF}')"
fi

OUT_FILE="release-manifest_${GIT_SHA:0:7}_$(date -u +%Y%m%dT%H%M%SZ).json"

cat > "$OUT_FILE" <<EOF
{
  "git": {
    "commit_sha": "$GIT_SHA",
    "branch_or_tag": "$GIT_REF"
  },
  "app_version": {
    "semantic_version": "$SEMANTIC_VERSION",
    "build_number": "$BUILD_NUMBER"
  },
  "environment": "$ENVIRONMENT",
  "flutter_sdk_version": "$FLUTTER_VERSION",
  "build_timestamp_utc": "$BUILD_TIMESTAMP",
  "artifact": {
    "type": "$ARTIFACT_TYPE",
    "path": "$ARTIFACT_PATH",
    "sha256": "$ARTIFACT_SHA256",
    "size_bytes": $ARTIFACT_SIZE
  },
  "signing": {
    "certificate_cn": "$CERT_CN",
    "certificate_sha256": "$CERT_SHA256"
  },
  "edge_functions": {
    "_comment": "MANUAL ENTRY REQUIRED - run: supabase functions list --project-ref <ref>",
    "dr-niswah-chat": "",
    "fiqh-advisor-chat": "",
    "dream-interpreter-chat": "",
    "ai-assistant-chat": ""
  },
  "db_migration_state": {
    "_comment": "MANUAL ENTRY REQUIRED - run: supabase migration list --linked",
    "last_applied_migration": ""
  },
  "verification": {
    "dart_analyze_issue_count": null,
    "flutter_test_pass_count": null,
    "flutter_test_total_count": null,
    "artifact_inspection_checklist_passed": null
  }
}
EOF

echo "Manifest written: $OUT_FILE"
echo "Fill in edge_functions and db_migration_state manually before archiving."
