#!/usr/bin/env bash
# Chooses which release .env secret content to write for a given app_env,
# and never falls back from one environment's secret to the other's.
#
# Factored out of routine-release.yml so this selection logic is unit-
# testable (see test_select_release_env_secret.py) without needing real
# secrets in CI — the test passes plain strings in place of secret values.
#
# Usage: select_release_env_secret.sh <production|staging>
#   Reads PRODUCTION_ENV_FILE_CONTENTS and STAGING_ENV_FILE_CONTENTS from
#   the environment. Prints the selected contents to stdout and exits 0
#   on success. Prints a clear error to stderr and exits 1 if the
#   required secret for the requested app_env is empty/unset — never
#   substitutes the other environment's value.
set -euo pipefail

app_env="${1:-}"
if [ -z "$app_env" ]; then
  echo "Usage: select_release_env_secret.sh <production|staging>" >&2
  exit 1
fi

case "$app_env" in
  production)
    secret_name="EMERGENCY_BUILD_ENV_FILE"
    contents="${PRODUCTION_ENV_FILE_CONTENTS:-}"
    ;;
  staging)
    secret_name="STAGING_BUILD_ENV_FILE"
    contents="${STAGING_ENV_FILE_CONTENTS:-}"
    ;;
  *)
    echo "Unknown app_env '$app_env' — must be 'production' or 'staging'." >&2
    exit 1
    ;;
esac

if [ -z "$contents" ]; then
  echo "$secret_name secret is not configured for app_env=$app_env." \
    "This workflow cannot produce a real release artifact without it," \
    "and will never fall back to a different environment's secret." >&2
  exit 1
fi

printf '%s' "$contents"
