#!/system/bin/sh
# ============================================================
# Metroid Service Recovery — Меню сервисных утилит
# ------------------------------------------------------------
# Запуск из терминала OFRP или:  adb shell sh /of_menu.sh
# ============================================================
while true; do
  echo ""
  echo "=========================================="
  echo "   METROID SERVICE RECOVERY — УТИЛИТЫ"
  echo "=========================================="
  echo "  1) Диагностика (dmesg/pstore/health -> /tmp)"
  echo "  2) Тест железа (батарея/тач/вибро/glyph)"
  echo "  3) Дамп critical-разделов (persist/modem)"
  echo "  4) Быстрый статус (батарея/темп/разделы)"
  echo "  5) Проверка ФС (fsck metadata/cache)"
  echo "  0) Выход"
  echo "------------------------------------------"
  printf "  выбор: "
  read CH
  case "$CH" in
    1) sh /of_diag.sh ;;
    2) sh /of_hwtest.sh ;;
    3) echo "Куда дамп? (/tmp или /usb_otg):"; read D; sh /of_partdump.sh "${D:-/tmp}" ;;
    4)
       echo "Батарея: $(cat /sys/class/power_supply/battery/capacity 2>/dev/null)% $(cat /sys/class/power_supply/battery/status 2>/dev/null)"
       echo "Темп CPU: $(($(cat /sys/class/thermal/thermal_zone6/temp 2>/dev/null)/1000))°C"
       echo "Разделы:"; ls /dev/block/by-name/ 2>/dev/null | tr '\n' ' '; echo ""
       ;;
    5)
       echo "fsck metadata (f2fs):"
       fsck.f2fs -f /dev/block/by-name/metadata 2>&1 | tail -5
       ;;
    0) exit 0 ;;
    *) echo "неизвестный выбор" ;;
  esac
done
