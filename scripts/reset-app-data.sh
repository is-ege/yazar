#!/bin/bash
# Resets Yazar to the state of a fresh install for local demos.
set -euo pipefail

bundle_id="egeis.yazar"
keychain_service="ai.yazar.credentials"
preferences_domain="$HOME/Library/Preferences/$bundle_id"
legacy_preferences_domain="$HOME/Library/Containers/$bundle_id/Data/Library/Preferences/$bundle_id"
application_support_directory="$HOME/Library/Application Support/Yazar"
# The single-slot layout Yazar shipped first, cleared too so a reset is a reset
# even on a machine that has not launched the migrating build yet.
legacy_keychain_service="ai.yazar.openrouter"
legacy_keychain_account="api-key"

if pgrep -x yazar >/dev/null 2>&1; then
  pkill -x yazar 2>/dev/null || true
  for _ in {1..50}; do
    if ! pgrep -x yazar >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
  if pgrep -x yazar >/dev/null 2>&1; then
    echo "could not stop Yazar; reset aborted before deleting data" >&2
    exit 1
  fi
fi

# Use explicit paths because a leftover sandbox container can make `defaults`
# resolve the bundle identifier to the wrong preferences file.
defaults delete "$preferences_domain" >/dev/null 2>&1 || true
defaults delete "$legacy_preferences_domain" >/dev/null 2>&1 || true

rm -rf -- "$application_support_directory"

delete_password() {
  if security find-generic-password -s "$1" -a "$2" >/dev/null 2>&1; then
    security delete-generic-password -s "$1" -a "$2" >/dev/null
  fi
}

delete_passwords_for_service() {
  while security find-generic-password -s "$1" >/dev/null 2>&1; do
    security delete-generic-password -s "$1" >/dev/null
  done
}

delete_passwords_for_service "$keychain_service"
delete_password "$legacy_keychain_service" "$legacy_keychain_account"

tccutil reset Microphone "$bundle_id"
tccutil reset Accessibility "$bundle_id"
tccutil reset ScreenCapture "$bundle_id"

echo "reset Yazar preferences, meeting history, API keys, and privacy permissions"
echo "to demo Globe key setup, change 'Press Globe key to' away from 'Do Nothing' in System Settings"
