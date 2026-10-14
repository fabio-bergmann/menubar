#!/usr/bin/env bash
# Creates the self-signed code signing certificate that scripts/build-app.sh
# signs with, in the login keychain, unless it's there already. Run it once
# per Mac.
#
#   scripts/make-signing-cert.sh
#
# Why: macOS ties an app's Accessibility grant to its code signature. An
# ad-hoc signature changes with every build, so every build lost the grant.
# A certificate's signature names the certificate instead, so the grant
# survives rebuilds and updates. It's self-signed and never trusted system
# wide: it only has to stay the same, and the app never leaves this Mac.
set -euo pipefail

NAME="Fabio Local Code Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "\"$NAME\" is already in the login keychain."
  exit 0
fi

WORK="$(mktemp -d -t menubar-cert)"
trap 'rm -rf "$WORK"' EXIT

cat >"$WORK/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

# macOS's own LibreSSL: its .p12 files are ones the keychain can import
# (Homebrew's OpenSSL 3 would need -legacy).
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$WORK/cert.conf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
PASSWORD="$(uuidgen)"
/usr/bin/openssl pkcs12 -export -name "$NAME" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/identity.p12" -passout "pass:$PASSWORD"

# codesign may use the key without asking each time.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
echo "Added \"$NAME\" to the login keychain."
