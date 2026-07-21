#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is not installed. Install it with: brew install xcodegen"
  exit 1
fi

rm -rf MyApps.xcodeproj
xcodegen generate --spec project.yml
open MyApps.xcodeproj
