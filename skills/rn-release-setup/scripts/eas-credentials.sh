#!/usr/bin/env bash
# Put credentials on EAS by driving `eas credentials` menus — no secret is read, typed or printed.
#
# Usage: eas-credentials.sh <project-dir> <android|ios> <build-profile> <task> [options]
#
# Tasks:
#   build-from-json   upload the keystore (android) or distribution certificate + provisioning
#                     profile (ios) from the project's credentials.json — paths and passwords in it
#                     were filled by the developer; this script only checks the file exists
#   submit-key        android: Google service account key for Play Store submissions (--key)
#                     ios: App Store Connect API key for EAS Submit (--key --key-id --issuer-id --team-id)
#   push-key          android: Google service account key for FCM V1 (--key)
#                     ios: APNs key (--key --key-id --team-id)
#
# Options: --key <path> --key-id <id> --issuer-id <id> --team-id <id>
#          --team-type COMPANY_OR_ORGANIZATION|INDIVIDUAL|IN_HOUSE (default COMPANY_OR_ORGANIZATION)
#          --eas-cli <version>   (default 25.3.0 — the menus this script knows)
#
# Needs `expect` (macOS and most Linux; not Git Bash on Windows → exit 2 with the manual command).
# Exit codes: 0 done · 1 error · 2 waiting on the developer (password / Apple login / no expect —
#             prints the command to run by hand) · 3 stopped on a decision (already set up, key not
#             valid on Apple's servers, a menu this script doesn't know)

set -euo pipefail
[ $# -ge 4 ] || { echo "usage: eas-credentials.sh <project-dir> <android|ios> <profile> <task> [options]" >&2; exit 1; }
project="$(cd "$1" && pwd)"; platform="$2"; profile="$3"; task="$4"; shift 4
key=""; key_id=""; issuer=""; team=""; team_type="COMPANY_OR_ORGANIZATION"; version="25.3.0"
while [ $# -gt 0 ]; do
  case "$1" in
    --key) key="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"; shift 2 ;;
    --key-id) key_id="$2"; shift 2 ;;
    --issuer-id) issuer="$2"; shift 2 ;;
    --team-id) team="$2"; shift 2 ;;
    --team-type) team_type="$2"; shift 2 ;;
    --eas-cli) version="$2"; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 1 ;;
  esac
done
here="$(cd "$(dirname "$0")" && pwd)"
manual="npx eas-cli@$version credentials -p $platform   (profile: $profile)"

case "$platform:$task" in
  android:build-from-json|ios:build-from-json)
    [ -f "$project/credentials.json" ] || { echo "no credentials.json in $project" >&2; exit 1; }
    menu="credentials.json: Upload/Download|Upload credentials from credentials.json to EAS" ;;
  android:submit-key)
    menu="Google Service Account|Manage your Google Service Account Key for Play Store Submissions|Set up a Google Service Account Key for Play Store Submissions" ;;
  android:push-key)
    menu="Google Service Account|Manage your Google Service Account Key for Push Notifications (FCM V1)|Set up a Google Service Account Key for Push Notifications (FCM V1)" ;;
  ios:submit-key)
    menu="App Store Connect: Manage your API Key|Set up your project to use an API Key for EAS Submit" ;;
  ios:push-key)
    menu="Push Notifications: Manage your Apple Push Notifications Key|Set up your project to use Push Notifications" ;;
  *) echo "unknown task $task for $platform" >&2; exit 1 ;;
esac
case "$task" in submit-key|push-key) [ -f "$key" ] || { echo "--key must point to an existing file" >&2; exit 1; } ;; esac

if ! command -v expect >/dev/null 2>&1; then
  echo "ACTION REQUIRED"
  echo "This machine has no 'expect', so the menus can't be driven automatically. Run:"
  echo "  $manual"
  exit 2
fi

cd "$project"
set +e
EC_PLATFORM="$platform" EC_PROFILE="$profile" EC_MENU="$menu" EC_KEY="$key" EC_KEY_ID="$key_id" \
EC_ISSUER_ID="$issuer" EC_TEAM_ID="$team" EC_DEBUG="${EC_DEBUG:-}" EC_EAS_CLI="npx --yes eas-cli@$version" \
EXPO_APPLE_TEAM_ID="$team" EXPO_APPLE_TEAM_TYPE="$team_type" \
  expect -f "$here/eas-credentials.exp"
status=$?
set -e
if [ "$status" -eq 2 ]; then
  echo "ACTION REQUIRED"
  echo "This step needs a password or an Apple login, which only the developer types. Run:"
  echo "  $manual"
fi
exit "$status"
