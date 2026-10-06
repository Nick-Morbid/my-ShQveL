#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/mysql_common.sh"
[[ $# -eq 3 ]] || mysql_die "usage: $0 RUN_ID EPOCH_NAME LOCAL_DIR"

run_id="$1"; name="$2"; local_dir="$(readlink -m "$3")"
[[ "$run_id" =~ ^[A-Za-z0-9._-]+$ ]] || mysql_die "unsafe run ID"
mysql_require_dir "$local_dir"
findmnt -T "$MYSQL_NFS_ROOT" -n -o FSTYPE | grep -q '^nfs' || mysql_die "MySQL NFS root is not on NFS"
remote_run="$MYSQL_NFS_ROOT/$run_id"
remote_tmp="$remote_run/.$name.uploading"
remote_final="$remote_run/$name"
[[ ! -e "$remote_final" ]] || mysql_die "remote artifact already exists: $remote_final"
mkdir -p "$remote_run" "$remote_tmp"
rsync -rlt --checksum --no-owner --no-group --no-perms --partial --delete "$local_dir/" "$remote_tmp/"
(cd "$remote_tmp" && sha256sum -c checksums.sha256)
printf '{"verified_at":"%s","transport":"nfs-rsync","checksum":"sha256"}\n' \
  "$(date --iso-8601=ns)" > "$remote_tmp/upload-receipt.json"
date --iso-8601=seconds > "$remote_tmp/COMPLETE"
sync -f "$remote_tmp/COMPLETE" 2>/dev/null || sync
mv "$remote_tmp" "$remote_final"
sync -f "$remote_run" 2>/dev/null || sync
