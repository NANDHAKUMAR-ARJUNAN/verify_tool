#!/usr/bin/env bash
set -euo pipefail

# === Inputs ===
PDF_FILE="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBLIC_KEY="${SCRIPT_DIR}/public_key.pem"
TMP_DIR=$(mktemp -d)

# === Usage helper ===
usage() {
  echo "Usage: $0 certificate_signed.pdf"
  exit 1
}

# === Validate inputs ===
[[ -z "$PDF_FILE" ]] && usage
[[ ! -f "$PDF_FILE" ]] && {
  echo "❌ File not found: $PDF_FILE"
  exit 1
}
[[ ! -f "$PUBLIC_KEY" ]] && {
  echo "❌ Public key not found: $PUBLIC_KEY"
  exit 1
}

# === Extract embedded files ===
echo "📂 Extracting attachments from PDF..."
pdftk "$PDF_FILE" unpack_files output "$TMP_DIR"

# Expecting these files
DATA_JSON="${TMP_DIR}/device_info.json"
SIGNED_BIN="${TMP_DIR}/signed_hash.bin"
HASH_BIN="${TMP_DIR}/data_hash.bin"

[[ ! -f "$DATA_JSON" || ! -f "$SIGNED_BIN" || ! -f "$HASH_BIN" ]] && {
  echo "❌ Required embedded files not found in PDF."
  exit 1
}

# === Recompute hash of JSON ===
echo "🔒 Computing SHA-256 hash of JSON..."
openssl dgst -sha256 -binary "$DATA_JSON" >"${TMP_DIR}/rehash.bin"

# === Compare stored hash vs recomputed hash ===
if cmp -s "$HASH_BIN" "${TMP_DIR}/rehash.bin"; then
  echo "✅ Hash check passed (JSON integrity verified)."
else
  echo "❌ Hash mismatch! Certificate JSON was altered."
  exit 1
fi

# === Verify signature ===
echo "🔑 Verifying digital signature..."
if openssl pkeyutl -verify -inkey "$PUBLIC_KEY" -pubin -sigfile "$SIGNED_BIN" -in "$HASH_BIN"; then
  echo "✅ Signature valid (certificate authentic)."
else
  echo "❌ Signature verification failed!"
  exit 1
fi

echo "🎉 Verification complete. Certificate is authentic and unmodified."
