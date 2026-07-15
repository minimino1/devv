#!/system/bin/sh
# ============================================================
# Metroid Service Recovery — Тест железа (of_hwtest)
# ------------------------------------------------------------
# Быстрая проверка компонентов. Неразрушающий.
#   sh /of_hwtest.sh
# ============================================================

echo "===== Metroid HW Test ====="

# --- Батарея ---
BAT=/sys/class/power_supply/battery
echo ""
echo "[БАТАРЕЯ]"
echo "  Заряд:    $(cat $BAT/capacity 2>/dev/null)%"
echo "  Статус:   $(cat $BAT/status 2>/dev/null)"
echo "  Здоровье: $(cat $BAT/health 2>/dev/null)"
echo "  Темп:     $(cat $BAT/temp 2>/dev/null) (0.1°C)"
echo "  Вольтаж:  $(cat $BAT/voltage_now 2>/dev/null) uV"
DES=$(cat $BAT/charge_full_design 2>/dev/null)
FUL=$(cat $BAT/charge_full 2>/dev/null)
if [ -n "$DES" ] && [ -n "$FUL" ] && [ "$DES" -gt 0 ]; then
  WEAR=$(( 100 - (FUL * 100 / DES) ))
  echo "  Износ:    ~${WEAR}% (full=$FUL design=$DES)"
fi

# --- Тач ---
echo ""
echo "[ТАЧСКРИН]"
ls /dev/input/ 2>/dev/null | while read i; do
  echo "  input: $i"
done
lsmod 2>/dev/null | grep -iE 'focaltech|touchpanel|st_fts' | while read m; do
  echo "  driver: $(echo $m | awk '{print $1}')"
done

# --- Glyph-матрица (фишка NP3) ---
echo ""
echo "[GLYPH MATRIX]"
GLYPH=$(find /sys -iname '*matrix*led*' -o -iname '*glyph*' 2>/dev/null | head -3)
if [ -n "$GLYPH" ]; then
  echo "  найдено: $GLYPH"
  lsmod 2>/dev/null | grep -i matrix | while read m; do echo "  driver: $(echo $m|awk '{print $1}')"; done
else
  echo "  matrix-leds драйвер: $(lsmod 2>/dev/null | grep -i matrix | awk '{print $1}')"
  echo "  (для теста паттернов нужен доступ к LED sysfs — TODO расширить)"
fi

# --- Вибро ---
echo ""
echo "[ВИБРО]"
VIB=$(find /sys/class -iname '*vibrat*' -o -iname '*haptic*' 2>/dev/null | head -2)
[ -n "$VIB" ] && echo "  найдено: $VIB"
lsmod 2>/dev/null | grep -iE 'haptic|vibrat' | while read m; do echo "  driver: $(echo $m|awk '{print $1}')"; done

# --- Экран/подсветка ---
echo ""
echo "[ДИСПЛЕЙ]"
echo "  Яркость:  $(cat /sys/class/backlight/panel0-backlight/brightness 2>/dev/null) / $(cat /sys/class/backlight/panel0-backlight/max_brightness 2>/dev/null)"
lsmod 2>/dev/null | grep -iE 'msm_drm|panel' | head -2 | while read m; do echo "  driver: $(echo $m|awk '{print $1}')"; done

# --- Температуры (сводка) ---
echo ""
echo "[ТЕМПЕРАТУРЫ > 40°C]"
for z in /sys/class/thermal/thermal_zone*/temp; do
  [ -e "$z" ] || continue
  T=$(cat "$z" 2>/dev/null)
  [ "$T" -gt 40000 ] 2>/dev/null && echo "  $(cat ${z%temp}type 2>/dev/null) = $((T/1000))°C"
done

echo ""
echo "===== конец теста ====="
