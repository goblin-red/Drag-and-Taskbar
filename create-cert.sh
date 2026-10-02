#!/bin/bash
set -euo pipefail

CERT_CN="TwoFingerDrag Codesign"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# Если идентичность уже есть — ничего не делаем.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_CN"; then
    echo "Сертификат «$CERT_CN» уже существует."
    security find-identity -v -p codesigning
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/openssl.cnf" <<CONF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = ${CERT_CN}
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONF

echo "==> Генерация ключа и самоподписанного сертификата…"
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -config "$TMP/openssl.cnf"

# -legacy: алгоритмы PKCS12, совместимые с macOS `security` (OpenSSL 3 иначе шифрует AES-256).
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -passout pass:tfdcert -name "$CERT_CN"

echo "==> Импорт в login keychain…"
# -A разрешает любым приложениям использовать ключ (чтобы codesign не спрашивал).
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P tfdcert -A -T /usr/bin/codesign

echo ""
echo "Готово."
security find-identity -v -p codesigning
