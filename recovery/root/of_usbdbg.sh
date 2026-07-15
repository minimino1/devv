#!/system/bin/sh
# ============================================================
# Metroid Service Recovery — USB gadget bring-up (of_usbdbg)
# ТОЛЬКО USB. UCSI не работает в recovery → форсим device-режим.
# НЕ трогает ADSP/thermal/redriver (вызывали power-краши/недетерминизм).
# ============================================================

LOG=/persist/of_usb.log
echo "=== USB bring-up $(cat /proc/uptime 2>/dev/null | cut -d. -f1)s ===" > "$LOG"

setprop sys.usb.ffs.ready 1
setprop sys.usb.config none
sleep 0.5
setprop sys.usb.config adb
sleep 1

if [ -e /config/usb_gadget/g1 ]; then
  echo 0x18D1 > /config/usb_gadget/g1/idVendor 2>>"$LOG"
  echo 0xD001 > /config/usb_gadget/g1/idProduct 2>>"$LOG"
  ln -sf /config/usb_gadget/g1/functions/ffs.adb /config/usb_gadget/g1/configs/b.1/f1 2>>"$LOG"
  echo "a600000.dwc3" > /config/usb_gadget/g1/UDC 2>>"$LOG"
  echo "UDC bound: $(cat /config/usb_gadget/g1/UDC 2>/dev/null)" >> "$LOG"
fi

echo normal > /sys/devices/platform/soc/a600000.ssusb/orientation 2>>"$LOG"
echo peripheral > /sys/devices/platform/soc/a600000.ssusb/mode 2>>"$LOG"
for rs in /sys/class/usb_role/*/role; do
  [ -e "$rs" ] || continue
  echo device > "$rs" 2>>"$LOG"
done

ls /sys/class/udc/ >> "$LOG" 2>&1
echo "done" >> "$LOG"
