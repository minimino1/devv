#!/system/bin/sh
# ============================================================
# Metroid Service Recovery — Диагностический сборщик (of_diag)
# ------------------------------------------------------------
# НЕРАЗРУШАЮЩИЙ. Только чтение. Собирает всё в /tmp/diag,
# упаковывает в /tmp/metroid_diag.tar.gz — забирай через:
#   adb pull /tmp/metroid_diag.tar.gz
#
# Запуск:  adb shell sh /of_diag.sh
# ============================================================

OUT=/tmp/diag
rm -rf "$OUT"; mkdir -p "$OUT"
TS=$(cat /proc/uptime 2>/dev/null | cut -d. -f1)
echo "Metroid diag — uptime ${TS}s" > "$OUT/00_info.txt"
getprop ro.build.date >> "$OUT/00_info.txt" 2>/dev/null
echo "--- collecting, wait ---"

# --- 1. Ядро/загрузка: почему падало/ребутилось ---
dmesg > "$OUT/01_dmesg.txt" 2>&1
# pstore — крэши прошлой загрузки (самое ценное для forensics)
if [ -d /sys/fs/pstore ]; then
  mkdir -p "$OUT/pstore"
  cp -a /sys/fs/pstore/* "$OUT/pstore/" 2>/dev/null
  ls -la /sys/fs/pstore/ > "$OUT/02_pstore_list.txt" 2>&1
fi
# last_kmsg / console-ramoops
cat /proc/last_kmsg > "$OUT/03_last_kmsg.txt" 2>/dev/null
# pmsg (последние сообщения logd/init перед крэшем)
cat /dev/pmsg0 > "$OUT/04_pmsg0.txt" 2>/dev/null
# reboot reason (Nothing/QTI)
cat /sys/module/qcom_reboot_reason/parameters/* > "$OUT/05_reboot_reason.txt" 2>/dev/null
getprop | grep -iE 'bootreason|boot.reason|last.reboot|reboot_reason' >> "$OUT/05_reboot_reason.txt" 2>/dev/null

# --- 2. Питание/батарея (health) ---
{
  echo "=== power_supply ==="
  for ps in /sys/class/power_supply/*/; do
    [ -d "$ps" ] || continue
    echo "--- $(basename $ps) ---"
    for f in capacity status health present temp voltage_now current_now charge_full charge_full_design cycle_count technology; do
      [ -e "$ps$f" ] && echo "  $f = $(cat $ps$f 2>/dev/null)"
    done
  done
} > "$OUT/10_battery.txt" 2>&1

# --- 3. Температуры (все зоны) ---
{
  echo "=== thermal zones ==="
  for z in /sys/class/thermal/thermal_zone*; do
    [ -e "$z/temp" ] || continue
    T=$(cat "$z/temp" 2>/dev/null)
    TYPE=$(cat "$z/type" 2>/dev/null)
    echo "  $TYPE = $T"
  done
} > "$OUT/11_thermal.txt" 2>&1

# --- 4. Разделы / блочные устройства (GPT, mapper, размеры) ---
{
  echo "=== by-name partitions ==="
  ls -la /dev/block/by-name/ 2>/dev/null
  echo ""
  echo "=== mapper (logical) ==="
  ls -la /dev/block/mapper/ 2>/dev/null
  echo ""
  echo "=== mounts ==="
  mount 2>/dev/null
  echo ""
  echo "=== df ==="
  df -h 2>/dev/null
  echo ""
  echo "=== GPT (main disk sda) ==="
  sgdisk -p /dev/block/sda 2>/dev/null
} > "$OUT/20_partitions.txt" 2>&1

# --- 5. UFS накопитель (health/lifetime) ---
{
  echo "=== UFS health ==="
  for h in /sys/devices/platform/soc/*.ufshc/health_descriptor/*; do
    [ -e "$h" ] && echo "  $(basename $h) = $(cat $h 2>/dev/null)"
  done
  echo "=== UFS device info ==="
  for d in /sys/devices/platform/soc/*.ufshc/device_descriptor/*; do
    [ -e "$d" ] && echo "  $(basename $d) = $(cat $d 2>/dev/null)"
  done
} > "$OUT/21_ufs_health.txt" 2>&1

# --- 6. Модули ядра / драйверы ---
lsmod > "$OUT/30_lsmod.txt" 2>&1
ls /dev/input/ > "$OUT/31_input_devices.txt" 2>&1

# --- 7. Состояние системы ---
getprop > "$OUT/40_getprop.txt" 2>&1
getenforce > "$OUT/41_selinux.txt" 2>&1
cat /proc/cmdline > "$OUT/42_cmdline.txt" 2>&1
cat /proc/meminfo > "$OUT/43_meminfo.txt" 2>&1
ps -A > "$OUT/44_processes.txt" 2>&1

# --- 8. Логи logd (если поднят) ---
logcat -d > "$OUT/50_logcat.txt" 2>&1

# --- Упаковка ---
cd /tmp
tar -czf /tmp/metroid_diag.tar.gz -C /tmp diag 2>/dev/null
SIZE=$(ls -la /tmp/metroid_diag.tar.gz 2>/dev/null | awk '{print $5}')
echo ""
echo "=========================================="
echo " Готово. Архив: /tmp/metroid_diag.tar.gz (${SIZE} bytes)"
echo " Забери: adb pull /tmp/metroid_diag.tar.gz"
echo "=========================================="
