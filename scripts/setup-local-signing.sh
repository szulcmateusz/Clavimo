#!/bin/sh
# Creates a self-signed code signing identity in a dedicated keychain for
# local development builds. Signing with a stable identity lets macOS keep
# Accessibility and Input Monitoring grants across rebuilds; ad-hoc
# signatures change with every build and lose them.
#
# The certificate is not trusted system-wide and is not added to the login
# keychain. It is only suitable for builds you run on this Mac.
# Remove it with: rm -rf "$HOME/Library/Application Support/ClavimoDev"
set -eu

DIR="$HOME/Library/Application Support/ClavimoDev"
KEYCHAIN="$DIR/signing.keychain-db"
NAME="Clavimo Local Development"

if [ -f "$KEYCHAIN" ]; then
    echo "Local signing identity already exists in $KEYCHAIN"
    exit 0
fi

mkdir -p "$DIR"
chmod 700 "$DIR"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

PASSWORD=$(openssl rand -hex 24)
printf '%s' "$PASSWORD" > "$DIR/keychain-password"
chmod 600 "$DIR/keychain-password"

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$PASSWORD" 2>/dev/null \
    || openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
        -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$PASSWORD"

security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null 2>&1 || true

echo "Created local signing identity \"$NAME\" in $KEYCHAIN"
