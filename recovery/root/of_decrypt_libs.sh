#!/system/bin/sh
# ============================================================
# Copy A16 namespace libs into /persist/decrypt_libs at boot.
# /persist is a separate partition (not in ramdisk), so libs shipped
# in ramdisk (/system/lib64_a16) are copied here on first boot.
# Required for the qseecomd/KeyMint namespace (see DECRYPT_FINDINGS.md).
# ============================================================
SRC=/system/lib64_a16
DST=/persist/decrypt_libs

if [ -d "$SRC" ] && [ "$(ls -A $SRC 2>/dev/null)" ]; then
  mkdir -p "$DST"
  for f in "$SRC"/*.so; do
    [ -e "$f" ] || continue
    cp -f "$f" "$DST/" 2>/dev/null
  done
  chmod 0644 "$DST"/*.so 2>/dev/null
fi
