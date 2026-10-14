#!/bin/bash
set -euo pipefail
umask 077
[[ -n "${GITHUB_ENV:-}" && -n "${RUNNER_TEMP:-}" ]] || { echo "This script requires a GitHub Actions runner." >&2; exit 1; }
if [[ -z "${APPLE_CERTIFICATE_BASE64:-}" && -z "${APPLE_CERTIFICATE_PASSWORD:-}" && -z "${APPLE_SIGNING_IDENTITY:-}" && -z "${APPLE_ID:-}" && -z "${APPLE_TEAM_ID:-}" && -z "${APPLE_APP_PASSWORD:-}" ]]; then
  echo "No Apple certificate configured: packaging will be ad-hoc signed, not notarized."
  exit 0
fi
: "${APPLE_CERTIFICATE_BASE64:?Certificate required}"
: "${APPLE_CERTIFICATE_PASSWORD:?Certificate password required}"
: "${APPLE_SIGNING_IDENTITY:?Signing identity required}"
if [[ -n "${APPLE_ID:-}" || -n "${APPLE_TEAM_ID:-}" || -n "${APPLE_APP_PASSWORD:-}" ]]; then
  : "${APPLE_ID:?Apple ID required}"
  : "${APPLE_TEAM_ID:?Team ID required}"
  : "${APPLE_APP_PASSWORD:?App-specific password required}"
fi
KEYCHAIN="$RUNNER_TEMP/mediaforge-signing.keychain-db"
PASSWORD="$(openssl rand -hex 32)"
echo "::add-mask::$PASSWORD"
CERTIFICATE="$RUNNER_TEMP/mediaforge-signing.p12"
trap 'rm -f "${CERTIFICATE:?}"' EXIT
printf '%s' "$APPLE_CERTIFICATE_BASE64" | /usr/bin/base64 -D > "$CERTIFICATE"
security create-keychain -p "$PASSWORD" "$KEYCHAIN"
printf 'MEDIAFORGE_KEYCHAIN=%s\n' "$KEYCHAIN" >> "$GITHUB_ENV"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$CERTIFICATE" -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -t cert -f pkcs12 -k "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN"
security list-keychains -d user -s "$KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db"
security find-identity -v -p codesigning "$KEYCHAIN"
printf 'APPLE_SIGNING_IDENTITY=%s\n' "$APPLE_SIGNING_IDENTITY" >> "$GITHUB_ENV"
if [[ -n "${APPLE_ID:-}" || -n "${APPLE_TEAM_ID:-}" || -n "${APPLE_APP_PASSWORD:-}" ]]; then
  xcrun notarytool store-credentials MediaForge --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --keychain "$KEYCHAIN"
  # The temporary keychain is in the user search list for the profile lookup.
  printf 'APPLE_NOTARY_PROFILE=MediaForge\n' >> "$GITHUB_ENV"
fi
