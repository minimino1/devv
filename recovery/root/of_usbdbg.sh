#!/system/bin/sh
# OFRP USB gadget diagnostics — writes state to /persist/of_debug.log
# Runs after post-fs. Samples every 3s for 30s total (10 samples).

SLOT=$(getprop ro.boot.slot_suffix)
LOG=/persist/of_debug.log
DMESG_LOG=/persist/of_dmesg.log

# === EARLY DMESG DUMP — до того как AVC-денаи забьют buffer ===
echo "=== EARLY DMESG (uptime $(cat /proc/uptime 2>/dev/null | cut -d. -f1)s) ===" > "$DMESG_LOG"
dmesg 2>&1 >> "$DMESG_LOG"

# === EARLY MODULE STATE ===
echo "=== EARLY LSMOD (uptime $(cat /proc/uptime 2>/dev/null | cut -d. -f1)s) ===" > /persist/of_lsmod.log
lsmod 2>&1 >> /persist/of_lsmod.log

echo "=== EARLY DRIVERS bus/platform ===" > /persist/of_drivers.log
ls /sys/bus/platform/drivers/ 2>&1 | grep -iE 'dwc|xhci|udc|gadget' >> /persist/of_drivers.log
echo "--- dwc3-msm attached devices ---" >> /persist/of_drivers.log
ls /sys/bus/platform/drivers/msm-dwc3/ 2>&1 >> /persist/of_drivers.log
echo "--- dwc3 (core) attached devices ---" >> /persist/of_drivers.log
ls /sys/bus/platform/drivers/dwc3/ 2>&1 >> /persist/of_drivers.log
echo "--- ssusb children ---" >> /persist/of_drivers.log
ls -la /sys/devices/platform/soc/a600000.ssusb/ 2>&1 >> /persist/of_drivers.log

echo "=== EARLY UDC ===" > /persist/of_udc.log
ls -la /sys/class/udc/ 2>&1 >> /persist/of_udc.log

echo "=== OFRP USB DEBUG — $(date 2>/dev/null || echo no-date) ===" > "$LOG"
echo "boot props:" >> "$LOG"
getprop | grep -iE '^\[(sys|ro).usb|^\[ro.boot.slot|^\[ro.boot.verified|^\[ro.debuggable|^\[ro.secure|^\[sys.usb.config|^\[sys.usb.controller|^\[sys.usb.state|^\[sys.usb.configfs|^\[sys.usb.ffs' >> "$LOG"
echo "" >> "$LOG"

# === VENDOR MOUNT CHECK ===
echo "=== vendor mount check ===" >> "$LOG"
ls /dev/block/mapper/ 2>&1 | grep -E 'vendor|system|super' >> "$LOG"
mount | grep -E '/vendor|mapper' >> "$LOG"
ls /vendor/etc/vintf/ 2>&1 | head -5 >> "$LOG"

# === MOUNT /vendor + START hwservicemanager (для FBE decrypt) ===
# mapper/vendor_a готов только сейчас (recovery активировал logical partitions)
echo "=== vendor mount + hwservicemanager ===" >> "$LOG"
if [ ! -f /vendor/etc/vintf/manifest.xml ] && [ ! -d /vendor/etc/vintf ]; then
  echo "mounting /vendor from mapper/vendor${SLOT}:" >> "$LOG"
  mount -t erofs -o ro /dev/block/mapper/vendor${SLOT} /vendor 2>&1 >> "$LOG"
  echo "  mount result: $?" >> "$LOG"
fi
ls /vendor/bin/qseecomd /vendor/bin/hw/android.hardware.keymaster@4.0-service-qti 2>&1 >> "$LOG"
# Проверяем smcinvoke device и модули (qseecomd их требует)
echo "smcinvoke device:" >> "$LOG"
ls -la /dev/smcinvoke 2>&1 >> "$LOG"
echo "smcinvoke modules:" >> "$LOG"
lsmod | grep -iE 'smcinvoke|qseecom_proxy|si_core|mem_object|tz_log' >> "$LOG"
# Стартуем HAL сервисы для decrypt
setprop ctl.start hwservicemanager 2>&1 >> "$LOG"
sleep 1
# Пробуем запустить qseecomd вручную с выводом ошибки (setcap/permission)
echo "=== manual qseecomd run ===" >> "$LOG"
chmod 660 /dev/smcinvoke 2>&1 >> "$LOG"
chown system:drmrpc /dev/smcinvoke 2>&1 >> "$LOG"
LD_LIBRARY_PATH=/vendor/lib64:/system/lib64 /vendor/bin/qseecomd > /persist/of_qseecomd.log 2>&1 &
QPID=$!
sleep 3
echo "qseecomd manual pid=$QPID alive=$(kill -0 $QPID 2>/dev/null && echo yes || echo no)" >> "$LOG"
echo "--- qseecomd stderr/stdout ---" >> "$LOG"
cat /persist/of_qseecomd.log >> "$LOG"
echo "--- end qseecomd output ---" >> "$LOG"
# logcat — qseecomd основные ошибки туда
echo "--- qseecomd logcat ---" >> "$LOG"
logcat -d 2>/dev/null | grep -iE 'qseecom|QSEE|smcinvoke|listener' | tail -20 >> "$LOG"
ps -A 2>/dev/null | grep -iE 'qseecomd' >> "$LOG"
echo "listeners after manual=$(getprop vendor.sys.listeners.registered)" >> "$LOG"
# Также через init
start vendor.qseecomd 2>&1 >> "$LOG"
setprop ctl.start vendor.qseecomd 2>&1 >> "$LOG"
sleep 2
echo "listeners.registered=$(getprop vendor.sys.listeners.registered)" >> "$LOG"
echo "qseecomd svc=$(getprop init.svc.vendor.qseecomd)" >> "$LOG"
ps -A 2>/dev/null | grep -iE 'qseecomd|keymaster|gatekeeper|hwservice' >> "$LOG"

# === STAGE -4: thermal fallback (governor + freq limits) ===
echo "=== thermal fallback ===" >> "$LOG"

# NP3 SM8735: policy0=little(LP), policy2=little+, policy5=mid, policy7=prime
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  [ -e "$p/scaling_governor" ] || continue
  NAME=$(basename $p)
  echo "before $p: $(cat $p/scaling_governor 2>/dev/null) avail: $(cat $p/scaling_available_governors 2>/dev/null)" >> "$LOG"
  # Приоритет: walt (как в системе NP3) → schedutil → powersave
  for g in walt schedutil powersave; do
    if grep -qw "$g" "$p/scaling_available_governors" 2>/dev/null; then
      echo "$g" > "$p/scaling_governor" 2>&1 >> "$LOG"
      echo "  set governor $g" >> "$LOG"
      break
    fi
  done
  # Лимит max_freq по кластеру (POSIX-совместимо, без ассоциативных массивов)
  case "$NAME" in
    policy0) LIMIT=1516800 ;;  # little LP
    policy2) LIMIT=1958400 ;;  # little+
    policy5) LIMIT=1804800 ;;  # mid
    policy7) LIMIT=2035200 ;;  # prime
    *)       LIMIT="" ;;
  esac
  if [ -n "$LIMIT" ] && [ -e "$p/scaling_max_freq" ]; then
    CURRENT_MAX=$(cat "$p/cpuinfo_max_freq" 2>/dev/null)
    echo "$LIMIT" > "$p/scaling_max_freq" 2>&1 >> "$LOG"
    echo "  set max_freq $LIMIT (was max $CURRENT_MAX)" >> "$LOG"
  fi
done
echo "thermal-engine-v2 pid: $(pidof thermal-engine-v2 2>/dev/null)" >> "$LOG"
echo "current temps:" >> "$LOG"
for z in /sys/class/thermal/thermal_zone*/temp; do
  [ -e "$z" ] || continue
  T=$(cat "$z" 2>/dev/null)
  TYPE=$(cat "${z%temp}type" 2>/dev/null)
  [ "$T" != "" ] && [ "$T" -gt 40000 ] && echo "  $TYPE = $T mC" >> "$LOG"
done

# === STAGE -3: manual insmod touch modules ===
echo "=== manual insmod touch stack ===" >> "$LOG"
for mod in panel_event_notifier touchpanel_event_notify qts focaltech_tp; do
  MOD_PATH=/vendor/lib/modules/$mod.ko
  if [ -f $MOD_PATH ]; then
    echo "insmod $mod:" >> "$LOG"
    insmod $MOD_PATH 2>&1 >> "$LOG"
    echo "  result: $?" >> "$LOG"
  else
    echo "$mod.ko NOT FOUND at $MOD_PATH" >> "$LOG"
  fi
done
echo "loaded modules after insmod:" >> "$LOG"
lsmod 2>&1 | grep -iE 'focaltech|panel_event|touchpanel|qts' >> "$LOG"
echo "input devices after insmod:" >> "$LOG"
ls /dev/input/ 2>&1 >> "$LOG"

# === STAGE -2: manually set ffs.ready + UDC ===
echo "=== manual ffs.ready + UDC bind ===" >> "$LOG"
echo "before ffs.ready=$(getprop sys.usb.ffs.ready)" >> "$LOG"
setprop sys.usb.ffs.ready 1 2>&1 >> "$LOG"
echo "after set ffs.ready=$(getprop sys.usb.ffs.ready)" >> "$LOG"

# Форс triger для binding: перезапишем sys.usb.config чтобы init re-parsed triggers
setprop sys.usb.config none 2>&1 >> "$LOG"
sleep 0.5
setprop sys.usb.config adb 2>&1 >> "$LOG"
sleep 1

# Прямой bind: если g1 существует, попробуем sами написать UDC
if [ -e /config/usb_gadget/g1 ]; then
  echo "=== direct g1 setup ===" >> "$LOG"
  # Создаём configuration
  echo 0x18D1 > /config/usb_gadget/g1/idVendor 2>&1
  echo 0xD001 > /config/usb_gadget/g1/idProduct 2>&1
  # Ссылка на functionfs
  ln -sf /config/usb_gadget/g1/functions/ffs.adb /config/usb_gadget/g1/configs/b.1/f1 2>&1 >> "$LOG"
  # Bind к UDC
  echo "trying to bind UDC:" >> "$LOG"
  echo "a600000.dwc3" > /config/usb_gadget/g1/UDC 2>&1 >> "$LOG"
  cat /config/usb_gadget/g1/UDC 2>&1 >> "$LOG"
  echo "UDC list:" >> "$LOG"
  ls /sys/class/udc/ 2>&1 >> "$LOG"
fi

# === STAGE -1: mount firmware + unbind/bind ADSP/CDSP ===
echo "=== check firmware mounted ===" >> "$LOG"
ls /vendor/firmware_mnt/image/adsp.mdt 2>&1 >> "$LOG"

# Форс mount если ещё не смонтировано (init мог не смочь)
if [ ! -f /vendor/firmware_mnt/image/adsp.mdt ]; then
  echo "attempt manual mount modem${SLOT} partition:" >> "$LOG"
  mkdir -p /vendor/firmware_mnt 2>&1 >> "$LOG"
  # A/B устройство — нужен явный slot suffix
  mount -o ro -t vfat /dev/block/by-name/modem${SLOT} /vendor/firmware_mnt 2>&1 >> "$LOG"
  echo "mount result: $?" >> "$LOG"
  ls /vendor/firmware_mnt/image/ 2>&1 | head -5 >> "$LOG"
fi

echo "=== set firmware search path ===" >> "$LOG"
cat /sys/module/firmware_class/parameters/path 2>&1 >> "$LOG"
echo "/vendor/firmware_mnt/image" > /sys/module/firmware_class/parameters/path 2>&1
echo "new firmware path:" >> "$LOG"
cat /sys/module/firmware_class/parameters/path 2>&1 >> "$LOG"

echo "=== unbind/rebind remoteproc-adsp + cdsp ===" >> "$LOG"
echo 3000000.remoteproc-adsp > /sys/bus/platform/drivers/qcom-q6v5-pas/unbind 2>&1 >> "$LOG"
echo 32300000.remoteproc-cdsp > /sys/bus/platform/drivers/qcom-q6v5-pas/unbind 2>&1 >> "$LOG"
sleep 1
echo 3000000.remoteproc-adsp > /sys/bus/platform/drivers/qcom-q6v5-pas/bind 2>&1 >> "$LOG"
echo 32300000.remoteproc-cdsp > /sys/bus/platform/drivers/qcom-q6v5-pas/bind 2>&1 >> "$LOG"
sleep 2
echo "state after rebind adsp:" >> "$LOG"
cat /sys/class/remoteproc/remoteproc1/state 2>&1 >> "$LOG"
cat /sys/class/remoteproc/remoteproc2/state 2>&1 >> "$LOG"

# === STAGE 0: unload + reload redriver (после инициализации всех регуляторов) ===
echo "=== reload redriver stack ===" >> "$LOG"
rmmod nb7vpq904m 2>&1 >> "$LOG"
rmmod redriver 2>&1 >> "$LOG"
sleep 1
insmod /vendor/lib/modules/redriver.ko 2>&1 >> "$LOG"
insmod /vendor/lib/modules/nb7vpq904m.ko 2>&1 >> "$LOG"
sleep 1
echo "after reload:" >> "$LOG"
ls /sys/bus/i2c/devices/ 2>&1 | grep -i 5-001c >> "$LOG"

# Пробую set orientation вручную + rebind (обход UCSI-supplier проблемы)
echo "=== set orientation + role manually ===" >> "$LOG"
echo "before orientation:" >> "$LOG"
cat /sys/devices/platform/soc/a600000.ssusb/orientation 2>&1 >> "$LOG"
cat /sys/devices/platform/soc/a600000.ssusb/mode 2>&1 >> "$LOG"

# force set orientation (normal), mode peripheral
echo normal > /sys/devices/platform/soc/a600000.ssusb/orientation 2>&1 >> "$LOG"
echo peripheral > /sys/devices/platform/soc/a600000.ssusb/mode 2>&1 >> "$LOG"

# КЛЮЧЕВОЕ: писать role = device в usb_role_switch (в системе так делает UCSI)
echo "=== set usb_role = device ===" >> "$LOG"
ls /sys/class/usb_role/ 2>&1 >> "$LOG"
for rs in /sys/class/usb_role/*/role; do
  [ -e "$rs" ] || continue
  echo "before $rs = $(cat $rs 2>/dev/null)" >> "$LOG"
  echo device > "$rs" 2>&1 >> "$LOG"
  echo "after $rs = $(cat $rs 2>/dev/null)" >> "$LOG"
done

echo "after set orientation:" >> "$LOG"
cat /sys/devices/platform/soc/a600000.ssusb/orientation 2>&1 >> "$LOG"
cat /sys/devices/platform/soc/a600000.ssusb/mode 2>&1 >> "$LOG"

echo "=== attempt driver_override to dwc3-of-simple ===" >> "$LOG"
echo a600000.ssusb > /sys/bus/platform/drivers/msm-dwc3/unbind 2>&1 >> "$LOG"
sleep 1
echo "dwc3-of-simple" > /sys/devices/platform/soc/a600000.ssusb/driver_override 2>&1 >> "$LOG"
cat /sys/devices/platform/soc/a600000.ssusb/driver_override 2>&1 >> "$LOG"
echo a600000.ssusb > /sys/bus/platform/drivers/dwc3-of-simple/bind 2>&1 >> "$LOG"
sleep 2
echo "after dwc3-of-simple bind, /sys/class/udc/:" >> "$LOG"
ls /sys/class/udc/ 2>&1 >> "$LOG"

echo "=== fallback: bind back msm-dwc3 ===" >> "$LOG"
echo a600000.ssusb > /sys/bus/platform/drivers/dwc3-of-simple/unbind 2>&1 >> "$LOG"
echo "" > /sys/devices/platform/soc/a600000.ssusb/driver_override 2>&1 >> "$LOG"
echo a600000.ssusb > /sys/bus/platform/drivers/msm-dwc3/bind 2>&1 >> "$LOG"
sleep 3
echo "after rebind, /sys/class/udc/:" >> "$LOG"
ls /sys/class/udc/ 2>&1 >> "$LOG"
echo "ssusb children after rebind:" >> "$LOG"
ls /sys/devices/platform/soc/a600000.ssusb/ 2>&1 | head -20 >> "$LOG"
echo "waiting_for_supplier content:" >> "$LOG"
cat /sys/devices/platform/soc/a600000.ssusb/waiting_for_supplier 2>&1 >> "$LOG"
echo "pmic_glink state:" >> "$LOG"
ls /sys/devices/platform/soc/soc:qcom,pmic_glink/ 2>&1 | head -20 >> "$LOG"
cat /sys/devices/platform/soc/soc:qcom,pmic_glink/waiting_for_supplier 2>&1 >> "$LOG"
echo "remoteproc adsp state (final):" >> "$LOG"
cat /sys/class/remoteproc/remoteproc1/state 2>&1 >> "$LOG"
echo "" >> "$LOG"

# Если UDC появился — сразу привяжем g1 к нему
if [ -e /sys/class/udc/a600000.dwc3 ]; then
  echo "=== UDC UP! Binding g1 to it ===" >> "$LOG"
  echo a600000.dwc3 > /config/usb_gadget/g1/UDC 2>&1 >> "$LOG"
  sleep 2
  cat /config/usb_gadget/g1/UDC 2>&1 >> "$LOG"
fi

for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  T=$(cat /proc/uptime | cut -d. -f1 2>/dev/null)
  echo "--- SAMPLE $i @ ${T}s uptime ---" >> "$LOG"

  echo "[UDC controllers]:" >> "$LOG"
  ls /sys/class/udc/ 2>&1 >> "$LOG"

  echo "[UDC state]:" >> "$LOG"
  for u in /sys/class/udc/*/state; do
    [ -e "$u" ] && echo "$u = $(cat $u 2>/dev/null)" >> "$LOG"
  done

  echo "[configfs mount]:" >> "$LOG"
  mount | grep -iE 'configfs|functionfs' >> "$LOG" 2>&1

  echo "[/config/usb_gadget tree]:" >> "$LOG"
  ls -la /config/usb_gadget/ 2>&1 >> "$LOG"
  ls -la /config/usb_gadget/g1/ 2>&1 >> "$LOG"

  echo "[g1 bindings]:" >> "$LOG"
  cat /config/usb_gadget/g1/UDC 2>&1 >> "$LOG"
  cat /config/usb_gadget/g1/idVendor 2>&1 >> "$LOG"
  cat /config/usb_gadget/g1/idProduct 2>&1 >> "$LOG"

  echo "[sys.usb props]:" >> "$LOG"
  getprop sys.usb.config >> "$LOG"
  getprop sys.usb.configfs >> "$LOG"
  getprop sys.usb.controller >> "$LOG"
  getprop sys.usb.state >> "$LOG"
  getprop sys.usb.ffs.ready >> "$LOG"
  getprop service.adb.root >> "$LOG"

  echo "[adbd status]:" >> "$LOG"
  getprop init.svc.adbd >> "$LOG"
  ps -A 2>/dev/null | grep -iE 'adbd' >> "$LOG"

  echo "[SELinux enforce]:" >> "$LOG"
  getenforce 2>&1 >> "$LOG"

  echo "" >> "$LOG"
  sleep 3
done

# === LATE DMESG (после всех sample'ов, для сравнения с early) ===
echo "=== LATE DMESG (uptime $(cat /proc/uptime 2>/dev/null | cut -d. -f1)s) ===" > /persist/of_dmesg_late.log
dmesg 2>&1 >> /persist/of_dmesg_late.log

echo "=== LATE UDC ===" >> /persist/of_udc.log
ls -la /sys/class/udc/ 2>&1 >> /persist/of_udc.log

echo "=== LATE DRIVERS ===" >> /persist/of_drivers.log
ls /sys/bus/platform/drivers/msm-dwc3/ 2>&1 >> /persist/of_drivers.log
ls -la /sys/devices/platform/soc/a600000.ssusb/ 2>&1 | grep -v supplier >> /persist/of_drivers.log

# === CRYPTO MONITOR — ждём пока OFRP UI запустится и вызовет Set_Crypto_State ===
echo "=== CRYPTO MONITOR (waiting for OFRP UI init) ===" >> "$LOG"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  sleep 3
  CS=$(getprop ro.crypto.state 2>/dev/null)
  CT=$(getprop ro.crypto.type 2>/dev/null)
  LS=$(getprop vendor.sys.listeners.registered 2>/dev/null)
  CR=$(getprop crypto.ready 2>/dev/null)
  T=$(cat /proc/uptime 2>/dev/null | cut -d. -f1)
  echo "[$T s] crypto.state=$CS type=$CT listeners=$LS crypto.ready=$CR" >> "$LOG"
  # Проверяем запустились ли сервисы decrypt
  ps -A 2>/dev/null | grep -iE 'qseecomd|keymaster|gatekeeper' >> "$LOG"
  # Если crypto.state уже encrypted — логируем детали
  if [ "$CS" = "encrypted" ]; then
    echo "  -> OFRP set crypto state! Checking services..." >> "$LOG"
    getprop init.svc.vendor.qseecomd >> "$LOG"
    getprop init.svc.keymaster-4-0 >> "$LOG"
    getprop init.svc.gatekeeper-1-0 >> "$LOG"
    break
  fi
done

sync
