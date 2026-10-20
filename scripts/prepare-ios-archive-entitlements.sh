#!/bin/bash
set -euo pipefail

# CI has no developer credentials. Preserve the requested capabilities in an
# ad-hoc signature so local xcodebuild -exportArchive can provision them.
archive_path="${1:?Usage: prepare-ios-archive-entitlements.sh ARCHIVE ENTITLEMENTS}"
entitlements_path="${2:?Usage: prepare-ios-archive-entitlements.sh ARCHIVE ENTITLEMENTS}"
app_path="$archive_path/Products/Applications/MyApps.app"

test -f "$app_path/Info.plist"
test -f "$entitlements_path"

# Frameworks must be signed before the containing app. They do not inherit
# the app's CloudKit or push entitlements.
if [[ -d "$app_path/Frameworks" ]]; then
  while IFS= read -r -d '' code_path; do
    codesign --force --sign - --timestamp=none "$code_path"
  done < <(find "$app_path/Frameworks" -depth \( -name '*.framework' -o -name '*.dylib' \) -print0)
fi

cp "$entitlements_path" "$app_path/archived-expanded-entitlements.xcent"
codesign --force --sign - --timestamp=none \
  --entitlements "$app_path/archived-expanded-entitlements.xcent" \
  "$app_path"
