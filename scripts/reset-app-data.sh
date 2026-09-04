#!/bin/bash
# Resets Yazar to the state of a fresh install for local demos.
set -euo pipefail

bundle_id="egeis.yazar"
keychain_service="ai.yazar.credentials"
meetings_directory="$HOME/Library/Application Support/Yazar/Meetings"
# The single-slot layout Yazar shipped first, cleared too so a reset is a reset
# even on a machine that has not launched the migrating build yet.
legacy_keychain_service="ai.yazar.openrouter"
legacy_keychain_account="api-key"

pkill -x yazar 2>/dev/null || true

if defaults read "$bundle_id" >/dev/null 2>&1; then
  defaults delete "$bundle_id"
fi

rm -rf -- "$meetings_directory"

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
