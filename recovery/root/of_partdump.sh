#!/system/bin/sh
# ============================================================
# Metroid Service Recovery — Дамп разделов (of_partdump)
# ------------------------------------------------------------
# Бэкап critical-разделов. НЕРАЗРУШАЮЩИЙ (только чтение dd if=).
#
# Использование:
#   sh /of_partdump.sh              — дамп critical в /tmp
#   sh /of_partdump.sh /usb_otg     — дамп на USB-OTG флешку
#   sh /of_partdump.sh /tmp modem   — дамп конкретного раздела
#
# Critical по умолчанию: persist modemst1 modemst2 fsg fsc
#   (то, что спасает IMEI/modem/калибровку при раскирпичивании)
# ============================================================

DEST="${1:-/tmp/partdump}"
SINGLE="$2"
mkdir -p "$DEST"

# critical разделы для спасения (modem/IMEI/persist/калибровка)
CRITICAL="persist modemst1 modemst2 fsg fsc bluetooth"

dump_one() {
  NAME="$1"
  SRC=$(readlink -f /dev/block/by-name/$NAME 2>/dev/null)
  [ -z "$SRC" ] && SRC=$(readlink -f /dev/block/bootdevice/by-name/$NAME 2>/dev/null)
  if [ -z "$SRC" ] || [ ! -e "$SRC" ]; then
    echo "  [skip] $NAME — не найден"
    return
  fi
  SZ=$(blockdev --getsize64 "$SRC" 2>/dev/null)
  echo "  [dump] $NAME ($SRC, ${SZ} bytes) -> $DEST/$NAME.img"
  dd if="$SRC" of="$DEST/$NAME.img" bs=4M 2>/dev/null
  echo "         result: $?"
}

if [ -n "$SINGLE" ]; then
  echo "=== dump single: $SINGLE ==="
  dump_one "$SINGLE"
else
  echo "=== dump critical partitions -> $DEST ==="
  for p in $CRITICAL; do
    dump_one "$p"
  done
fi

sync
echo ""
echo "Готово. Файлы в $DEST:"
ls -la "$DEST"/*.img 2>/dev/null
echo ""
echo "Забрать из /tmp:  adb pull $DEST"
