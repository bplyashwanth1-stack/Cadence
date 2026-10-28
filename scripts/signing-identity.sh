#!/bin/zsh
# Prints the SHA-1 of Cadence's local code-signing identity, creating it the first time.
#
# Ad-hoc signatures change with every build, so macOS treats each build as a new app and asks for the audio
# and Spotify permissions again. Signing every build with the same self-signed certificate keeps the app's
# identity stable, so permissions are remembered. The certificate lives in its own keychain, never leaves this
# Mac, and isn't trusted for anything else.
set -e
NAME="Cadence Local Signing"
KC=~/Library/Keychains/cadence-signing.keychain-db
PASS=cadence

if [ ! -f "$KC" ]; then
  tmp=$(mktemp -d)
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$NAME" \
    -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
  openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$NAME" \
    -out "$tmp/id.p12" -passout pass:$PASS 2>/dev/null
  security create-keychain -p $PASS "$KC"
  security set-keychain-settings "$KC"  # no auto-lock
  security import "$tmp/id.p12" -k "$KC" -P $PASS -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k $PASS "$KC" >/dev/null
  rm -rf "$tmp"
fi

# codesign only finds identities in keychains on the search list.
keychains=$(security list-keychains -d user | tr -d '"' | xargs)
if [[ "$keychains" != *cadence-signing* ]]; then
  security list-keychains -d user -s ${=keychains} "$KC"
fi
security unlock-keychain -p $PASS "$KC"
security find-certificate -c "$NAME" -Z "$KC" | awk '/SHA-1/ { print $3 }'
