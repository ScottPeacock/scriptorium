#!/usr/bin/env bash
# Builds a signed archive and exports an .ipa for App Store Connect.
#
#   ./Tools/archive.sh              # archive + export
#   ./Tools/archive.sh --upload     # ...and upload to TestFlight
#
# Uploading needs an App Store Connect API key. Create one at
# App Store Connect > Users and Access > Integrations > App Store Connect API
# (Developer role is enough for TestFlight), save the .p8 to
# ~/.appstoreconnect/private_keys/, and export:
#
#   export ASC_KEY_ID=XXXXXXXXXX
#   export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
ARCHIVE="build/Scriptorium.xcarchive"
EXPORT_DIR="build/export"

echo "==> Generating project"
xcodegen generate

echo "==> Archiving (build $BUILD)"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
xcodebuild archive \
  -project Scriptorium.xcodeproj \
  -scheme Scriptorium \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD" \
  | xcbeautify 2>/dev/null || xcodebuild archive \
      -project Scriptorium.xcodeproj \
      -scheme Scriptorium \
      -destination 'generic/platform=iOS' \
      -archivePath "$ARCHIVE" \
      -allowProvisioningUpdates \
      CURRENT_PROJECT_VERSION="$BUILD"

echo "==> Exporting"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist Support/ExportOptions.plist \
  -allowProvisioningUpdates

IPA="$(find "$EXPORT_DIR" -name '*.ipa' | head -1)"
echo "==> Built $IPA"

if [ "${1:-}" = "--upload" ]; then
  : "${ASC_KEY_ID:?set ASC_KEY_ID (see the comment at the top of this script)}"
  : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
  echo "==> Uploading to TestFlight"
  xcrun altool --upload-app \
    --type ios \
    --file "$IPA" \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID"
  echo "==> Uploaded. Processing takes a few minutes before it appears in TestFlight."
fi
