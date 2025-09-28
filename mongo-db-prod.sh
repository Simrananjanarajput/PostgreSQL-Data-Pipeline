#!/bin/bash
set -euo pipefail

# ================= Azure Storage (your SAS baked in) =================
CONTAINER_BASE="https://starteryoubackups.blob.core.windows.net/mongodb-backups"
RAW_SAS="sas "
# normalize to start with '?'
case "$RAW_SAS" in \?*) SAS_TOKEN="$RAW_SAS";; *) SAS_TOKEN="?$RAW_SAS";; esac
CONTAINER_URL="${CONTAINER_BASE}${SAS_TOKEN}"
# =====================================================================

# ================= MongoDB (PROD on this VM) =================
CA="/opt/starteryou/certs/mongodb-ca.crt"
PROD_HOSTNAME="starteryou-db-prod"
PROD_URI="mongodb://appUser:password!@${PROD_HOSTNAME}:27017/starteryou?authSource=starteryou&ssl=true"
# =====================================================================

# Tools / paths
AZ="/usr/bin/azcopy"; [ -x "$AZ" ] || AZ="$HOME/azcopy_linux_amd64_10.29.1/azcopy"
DATE="$(date +%F)"
TMP="/tmp/starteryou_prod_${DATE}.gz"

# Helpers
log(){ echo "[$(date -Is)] $*"; }

# -------- Sanity checks --------
[ -x "$AZ" ] || { echo "ERROR: azcopy not found"; exit 1; }
[ -f "$CA" ] || { echo "ERROR: CA file not found at $CA"; exit 1; }
[[ "$CONTAINER_URL" == *"?"* && "$CONTAINER_URL" == *"sig="* ]] || { echo "ERROR: SAS looks invalid"; exit 1; }

# Ensure hostname resolves locally to avoid TLS hostname mismatch
grep -qE "^[^#]*\b${PROD_HOSTNAME}\b" /etc/hosts || echo "127.0.0.1 ${PROD_HOSTNAME}" | sudo tee -a /etc/hosts >/dev/null

# Validate SAS first (fail fast if wrong/expired)
log "Checking SAS access…"
"$AZ" ls "$CONTAINER_URL" >/dev/null || { echo "ERROR: SAS invalid/expired or wrong container"; exit 1; }

# Build destination: insert blob path BEFORE the '?' query
BASE_NO_Q="${CONTAINER_URL%%\?*}"
QPART="${CONTAINER_URL#*\?}"
DEST="${BASE_NO_Q}/eastus/prod/starteryou_prod_${DATE}.gz?${QPART}"

# -------- Dump & Upload (with hostname check disabled) --------
log "Dumping PROD locally -> $TMP"
mongodump   --uri="$PROD_URI"   --ssl --sslCAFile="$CA"   --sslAllowInvalidHostnames   --archive="$TMP" --gzip

# If you still see TLS errors, UNCOMMENT the next two lines and try again:
# echo "[INFO] Retrying with --sslAllowInvalidCertificates as well"
# mongodump --uri="$PROD_URI" --ssl --sslCAFile="$CA" --sslAllowInvalidHostnames --sslAllowInvalidCertificates --archive="$TMP" --gzip

log "Uploading to Azure -> $DEST"
"$AZ" copy "$TMP" "$DEST" --overwrite=true

log "Cleaning up"
rm -f "$TMP"

log "✅ PROD backup uploaded for $DATE"
