#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/tidb_common.sh"
[[ $# -eq 3 ]] || tidb_die "usage: $0 RUN_ID NAME LOCAL_DIR"
run_id="$1"; name="$2"; local_dir="$(readlink -m "$3")"; [[ "$run_id" =~ ^[A-Za-z0-9._-]+$ ]] || tidb_die "unsafe run ID"
tidb_require_dir "$local_dir"; findmnt -T "$TIDB_NFS_ROOT" -n -o FSTYPE | grep -q '^nfs' || tidb_die "TiDB result root is not NFS"
remote_run="$TIDB_NFS_ROOT/$run_id"; tmp="$remote_run/.$name.uploading"; final="$remote_run/$name"
[[ ! -e "$final" ]] || tidb_die "remote artifact exists: $final"; mkdir -p "$remote_run" "$tmp"
rsync -rlt --checksum --no-owner --no-group --no-perms --partial --delete "$local_dir/" "$tmp/"
(cd "$tmp" && sha256sum -c checksums.sha256)
printf '{"verified_at":"%s","transport":"nfs-rsync","checksum":"sha256"}\n' "$(date --iso-8601=ns)" > "$tmp/upload-receipt.json"
date --iso-8601=seconds > "$tmp/COMPLETE"; sync -f "$tmp/COMPLETE" 2>/dev/null || sync; mv "$tmp" "$final"
