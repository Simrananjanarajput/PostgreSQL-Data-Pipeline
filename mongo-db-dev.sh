#!/bin/bash
# DEV backup — run this ON db (the DEV DB VM)
set -euo pipefail
log(){ echo "[$(date -Is)] $*"; }

# ===== Azure Storage (SAS baked in) =====
BASE="https://starteryoubackups.blob.core.windows.net/mongodb-backups"
SAS="Add -sas"

# ===== MongoDB (DEV) =====
USER="appUser"
PASS="password"
DB="yourdb name"
AUTHDB="hostname"

# Use this VM's primary IP to avoid DNS/SAN issues
DEV_IP="$(hostname -I | awk '{print $1}')"

# Tools / paths
AZ="/usr/bin/azcopy"
DATE="$(date +%F)"
TMP="/tmp/${DB}_dev_${DATE}.gz"
DEST="${BASE}/${DEST_DIR}/${DB}_dev_${DATE}.gz${SAS}"

# ---- Sanity checks ----
command -v mongodump >/dev/null || { echo "ERROR: mongodump not installed"; exit 1; }
[ -x "$AZ" ] || { echo "ERROR: azcopy not found at $AZ"; exit 1; }
[[ "$DEST" == *"sig="* ]] || { echo "ERROR: SAS missing/invalid"; exit 1; }

# Check mongod is up and port is listening
if ! sudo ss -tlnp | grep -q ':27017'; then
  echo "ERROR: mongod not listening on 27017"; sudo systemctl status mongod --no-pager || true; exit 1
fi

# Validate SAS (fail fast)
log "Checking SAS access…"
"$AZ" ls "${BASE}${SAS}" >/dev/null

# ---- Dump with TLS, but ignore cert verification/hostname (fixes SAN/CN issues) ----
log "Dumping DEV locally -> $TMP"
mongodump   --uri="mongodb://${USER}:${PASS}@${DEV_IP}:27017/${DB}?authSource=${AUTHDB}&ssl=true"   --tlsInsecure   --archive="$TMP"   --gzip

# ---- Upload to Azure ----
log "Uploading -> $DEST"
"$AZ" copy "$TMP" "$DEST" --overwrite=true

# ---- Cleanup ----
rm -f "$TMP"
log "✅ DEV backup uploaded for $DATE"
