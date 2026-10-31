#!/bin/sh
# Copy native Firebase configuration only for explicitly push-enabled builds.
set -eu
push=false
old_ifs=$IFS
IFS=,
for encoded in ${DART_DEFINES:-}; do
  decoded=$(printf '%s' "$encoded" | /usr/bin/base64 --decode 2>/dev/null) || exit 1
  if [ "$decoded" = 'NISWAH_PUSH_ENABLED=true' ]; then push=true; fi
done
IFS=$old_ifs
destination="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/GoogleService-Info.plist"
if [ "$push" != true ]; then
  # Remove only this script's generated resource to prevent stale configuration.
  rm -f "$destination"
  exit 0
fi
source="$SRCROOT/Runner/GoogleService-Info.plist"
if [ ! -f "$source" ]; then
  echo 'error: Push-enabled iOS build requires a validated GoogleService-Info.plist.' >&2
  exit 1
fi
bundle=$(/usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' "$source")
if [ "$bundle" != "$PRODUCT_BUNDLE_IDENTIFIER" ]; then
  echo 'error: Firebase Apple bundle ID differs from the signing bundle ID.' >&2
  exit 1
fi
for pair in 'FIREBASE_PROJECT_ID:PROJECT_ID' 'FIREBASE_IOS_APP_ID:GOOGLE_APP_ID' 'FIREBASE_MESSAGING_SENDER_ID:GCM_SENDER_ID' 'FIREBASE_API_KEY:API_KEY'; do
  define=${pair%%:*}
  key=${pair#*:}
  expected=$(/usr/libexec/PlistBuddy -c "Print :$key" "$source")
  [ -n "$expected" ] || exit 1
  matched=false
  IFS=,
  for encoded in ${DART_DEFINES:-}; do
    decoded=$(printf '%s' "$encoded" | /usr/bin/base64 --decode 2>/dev/null) || exit 1
    if [ "$decoded" = "$define=$expected" ]; then matched=true; fi
  done
  IFS=$old_ifs
  if [ "$matched" != true ]; then
    echo 'error: Firebase native plist and Dart configuration differ or are incomplete.' >&2
    exit 1
  fi
done
mkdir -p "$(dirname "$destination")"
cp "$source" "$destination"
echo 'Firebase native plist matches bundle ID and Dart options; bundled successfully.'
