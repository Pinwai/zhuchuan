#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_NAME="${BUILD_NAME:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-2}"
EXPORT_OPTIONS="${EXPORT_OPTIONS:-ios/ExportOptions-AppStore.plist}"

echo "== 珠串 TestFlight build =="
echo "Build: ${BUILD_NAME}+${BUILD_NUMBER}"
echo "Bundle ID: com.pinwai.zhuchuan"
echo

if ! security find-identity -v -p codesigning | grep -Eq 'Apple Distribution|iOS Distribution'; then
  cat <<'MSG'
Warning: no Apple/iOS Distribution signing identity was found in this keychain.
This Mac can create an archive, but App Store/TestFlight IPA export will fail
until an Apple Developer account with distribution permission is configured.
MSG
  echo
fi

flutter pub get

if [[ "${SKIP_CHECKS:-0}" != "1" ]]; then
  dart analyze
  flutter test
fi

flutter build ipa \
  --release \
  --build-name="$BUILD_NAME" \
  --build-number="$BUILD_NUMBER" \
  --export-options-plist="$EXPORT_OPTIONS"

IPA_PATH="$(find build/ios/ipa -maxdepth 1 -name '*.ipa' -print -quit 2>/dev/null || true)"
if [[ -z "$IPA_PATH" ]]; then
  cat <<'MSG'
No IPA was produced. Check the signing error above.
Most likely missing requirements:
- Apple/iOS Distribution certificate
- App Store provisioning profile for com.pinwai.zhuchuan
- App Store Connect app record for com.pinwai.zhuchuan
MSG
  exit 1
fi

echo "IPA created: $IPA_PATH"

if [[ -n "${ASC_API_KEY_ID:-}" && -n "${ASC_API_ISSUER_ID:-}" ]]; then
  xcrun altool --upload-app \
    --type ios \
    --file "$IPA_PATH" \
    --apiKey "$ASC_API_KEY_ID" \
    --apiIssuer "$ASC_API_ISSUER_ID"
  echo "Uploaded to App Store Connect. Wait for processing, then enable TestFlight."
else
  cat <<MSG
Upload skipped. To upload with an App Store Connect API key:

  export ASC_API_KEY_ID=YOUR_KEY_ID
  export ASC_API_ISSUER_ID=YOUR_ISSUER_ID
  # Put AuthKey_YOUR_KEY_ID.p8 in ~/.appstoreconnect/private_keys/
  scripts/build_testflight.sh

Or open the archive in Xcode Organizer:

  open build/ios/archive/Runner.xcarchive
MSG
fi
