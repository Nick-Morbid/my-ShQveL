#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
[[ $# -eq 3 ]] || die "usage: $0 RUN_ID EPOCH_NAME LOCAL_EPOCH_DIR"
RUN_ID="$1"
EPOCH_NAME="$2"
LOCAL_EPOCH="$(readlink -m "$3")"
require_dir "$LOCAL_EPOCH"
findmnt -T "$NFS_ROOT" -n -o FSTYPE | grep -q '^nfs' || die "NFS root is not mounted via NFS"

REMOTE_RUN="$NFS_ROOT/$RUN_ID"
REMOTE_TMP="$REMOTE_RUN/.${EPOCH_NAME}.uploading"
REMOTE_FINAL="$REMOTE_RUN/$EPOCH_NAME"
UPLOAD_START="$(date --iso-8601=ns)"
UPLOAD_START_NS="$(date +%s%N)"
mkdir -p "$REMOTE_RUN"
[[ ! -e "$REMOTE_FINAL/COMPLETE" ]] || die "remote epoch already complete: $REMOTE_FINAL"
mkdir -p "$REMOTE_TMP"
# Synology's NFS export uses root-squash and deliberately rejects chown/chmod.
# Preserve timestamps and links, but never attempt to copy Unix ownership/modes.
# --checksum is intentional: after a failed upload, a corrected manifest can
# have the same size and second-resolution mtime as the stale remote copy.
rsync -rlt --checksum --no-owner --no-group --no-perms --partial --delete "$LOCAL_EPOCH/" "$REMOTE_TMP/"
sync -f "$REMOTE_TMP" 2>/dev/null || sync
(cd "$REMOTE_TMP" && sha256sum -c checksums.sha256)
UPLOAD_END_NS="$(date +%s%N)"
cat > "$REMOTE_TMP/upload-receipt.json" <<EOF
{"started_at":"$UPLOAD_START","verified_at":"$(date --iso-8601=ns)","elapsed_seconds":$(( (UPLOAD_END_NS - UPLOAD_START_NS) / 1000000000 )),"transport":"nfs-rsync","checksum":"sha256"}
EOF
date --iso-8601=seconds > "$REMOTE_TMP/COMPLETE"
sync -f "$REMOTE_TMP/COMPLETE" 2>/dev/null || sync
mv "$REMOTE_TMP" "$REMOTE_FINAL"
sync -f "$REMOTE_RUN" 2>/dev/null || sync
