#!/bin/zsh
# Creates the self-signed certificate that release builds are signed with. Run it once.
#
#   zsh scripts/create-signing-certificate.sh [--upload]
#
# Every release must use the same certificate: installed copies only accept updates signed
# with it, and macOS keeps Still's Automation permission because the signature stays stable.
# Back up the folder this writes. --upload stores the certificate in this repository's
# Actions secrets with the GitHub CLI.
set -euo pipefail
cd "${0:A:h:h}"

dir=${STILL_SIGNING_DIR:-$HOME/.still-release-signing}
name="Still Release Signing"
if [[ -e $dir/still-signing.p12 ]]; then
  print "Using the existing certificate in $dir."
else
  mkdir -p "$dir" && chmod 700 "$dir"
  config=$(mktemp)
  trap 'rm -f "$config" "$dir/key.pem"' EXIT
  cat > "$config" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
  # LibreSSL's PKCS#12 defaults are the ones macOS's security tool imports.
  /usr/bin/openssl req -x509 -newkey rsa:3072 -nodes -days 7300 -config "$config" \
    -keyout "$dir/key.pem" -out "$dir/still-signing.pem" 2>/dev/null
  /usr/bin/openssl rand -base64 24 | tr -d '\n' > "$dir/p12-password.txt"
  /usr/bin/openssl pkcs12 -export -inkey "$dir/key.pem" -in "$dir/still-signing.pem" -name "$name" \
    -out "$dir/still-signing.p12" -passout "file:$dir/p12-password.txt"
  chmod 600 "$dir"/*
  print "Created a certificate in $dir. Back up this folder somewhere private."
fi
print "SHA-1: $(/usr/bin/openssl x509 -in "$dir/still-signing.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)"

if [[ ${1:-} == --upload ]]; then
  base64 -i "$dir/still-signing.p12" | gh secret set STILL_SIGNING_P12_BASE64
  gh secret set STILL_SIGNING_P12_PASSWORD < "$dir/p12-password.txt"
  print "Uploaded STILL_SIGNING_P12_BASE64 and STILL_SIGNING_P12_PASSWORD to GitHub Actions secrets."
fi
