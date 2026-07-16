DEVICE_PATH := device/nothing/Metroid

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-2a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := kryo

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-2a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := generic
TARGET_2ND_CPU_VARIANT_RUNTIME := kryo

# Platform
TARGET_BOARD_PLATFORM := sun

# Bootloader
TARGET_BOOTLOADER_BOARD_NAME := Metroid
TARGET_NO_BOOTLOADER := true

# Kernel — GKI 2.0, prebuilt из vendor_boot
BOARD_KERNEL_IMAGE_NAME := Image
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel
TARGET_PREBUILT_DTB    := $(DEVICE_PATH)/prebuilt/dtb.img

BOARD_KERNEL_BASE        := 0x00000000
BOARD_KERNEL_PAGESIZE    := 4096
BOARD_RAMDISK_OFFSET     := 0x01000000
BOARD_KERNEL_TAGS_OFFSET := 0x00000100

BOARD_BOOT_HEADER_VERSION := 4
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --dtb $(TARGET_PREBUILT_DTB)
PRODUCT_PRECOMPILED_SEPOLICY := false

# GKI 2.0 — init_boot содержит generic ramdisk (отключено: OFRP 12.1 не умеет init_boot)
# BOARD_INIT_BOOT_HEADER_VERSION := 4
# BOARD_MKBOOTIMG_INIT_ARGS += --header_version $(BOARD_INIT_BOOT_HEADER_VERSION)

# bootconfig (из реального устройства)
BOARD_KERNEL_CMDLINE := \
    video=vfb:640x400,bpp=32,memsize=3072000 \
    console=ttyMSM0,115200n8 \
    bootconfig

BOARD_BOOTCONFIG := \
    androidboot.hardware=qcom \
    androidboot.memcg=1 \
    androidboot.usbcontroller=a600000.dwc3 \
    androidboot.load_modules_parallel=false \
    androidboot.hypervisor.protected_vm.supported=true \
    androidboot.vendor.qspa=true \
    androidboot.serialconsole=0 \
    androidboot.selinux=permissive

# Разделы — реальные размеры
BOARD_BOOTIMAGE_PARTITION_SIZE            := 100663296
BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE      := 8388608
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE     := 100663296
BOARD_RECOVERYIMAGE_PARTITION_SIZE        := 104857600
BOARD_DTBOIMG_PARTITION_SIZE              := 52428800

# Super / динамические разделы
BOARD_SUPER_PARTITION_SIZE := 9663676416
BOARD_SUPER_PARTITION_GROUPS := nothing_dynamic_partitions
BOARD_NOTHING_DYNAMIC_PARTITIONS_PARTITION_LIST := \
    system \
    system_ext \
    product \
    vendor \
    odm \
    vendor_dlkm

BOARD_NOTHING_DYNAMIC_PARTITIONS_SIZE := 9659482112

# Файловые системы — system/vendor EROFS, data F2FS
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE      := erofs
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE      := erofs
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE     := erofs
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE  := erofs
BOARD_ODMIMAGE_FILE_SYSTEM_TYPE         := erofs
TARGET_USERIMAGES_USE_EXT4              := true
TARGET_USERIMAGES_USE_F2FS              := true
BOARD_EROFS_COMPRESSOR                  := lz4
BOARD_EROFS_PCLUSTER_SIZE               := 262144

TARGET_COPY_OUT_VENDOR                  := vendor
TARGET_COPY_OUT_PRODUCT                 := product
TARGET_COPY_OUT_SYSTEM_EXT              := system_ext
TARGET_COPY_OUT_ODM                     := odm

# UFS — реальный путь контроллера
TARGET_RECOVERY_DEVICE_DIRS += $(DEVICE_PATH)

# A/B
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += \
    boot \
    dtbo \
    vendor_boot \
    recovery \
    vbmeta \
    vbmeta_system \
    vbmeta_vendor

# Recovery
TARGET_RECOVERY_PIXEL_FORMAT         := RGBX_8888
TARGET_RECOVERY_QCOM_RTC_FIX         := true
BOARD_HAS_LARGE_FILESYSTEM           := true
BOARD_HAS_NO_SELECT_BUTTON           := true
BOARD_SUPPRESS_SECURE_ERASE          := true
BOARD_USES_RECOVERY_AS_BOOT          := false

# Имитируем структуру стокового recovery.img:
# - KERNEL_SZ=0 (bootloader берёт kernel из boot_a)
# - ramdisk сжат lz4_legacy (как сток)
# - наш ramdisk будет наложен поверх vendor_boot ramdisk при recovery-режиме
BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE := true
BOARD_RAMDISK_USE_LZ4                    := true

# Vendor modules для recovery — читаем актуальный список из стокового modules.load.recovery
# Модули-спамеры, забивающие kmsg — не нужны в recovery
TW_MODULE_BLACKLIST := aw9380x|aw_press

# Vendor modules для recovery — стоковый список минус blacklist
TW_LOAD_VENDOR_MODULES := "$(shell grep -vE '$(TW_MODULE_BLACKLIST)' $(DEVICE_PATH)/recovery/root/vendor/lib/modules/modules.load.recovery | tr '\n' ' ')"

TW_EXCLUDE_DEFAULT_USB_INIT := true

TW_DEFAULT_PROPS += \
	keymaster_ver=4.1
	sys.usb.configfs=1 \
	sys.usb.controller=a600000.dwc3 \
	ro.recovery.usb.vid=18D1 \
	ro.recovery.usb.adb.pid=D001 \
	ro.recovery.usb.fastboot.pid=4EE0

# Шифрование — отключаем для первого теста
TW_INCLUDE_CRYPTO          := true
TW_INCLUDE_CRYPTO_FBE      := true
TW_INCLUDE_FBE_METADATA_DECRYPT := true

# AVB
BOARD_AVB_ENABLE := true
BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --flags 3

# TWRP
TW_THEME                   := portrait_hdpi
TW_SCREEN_BLANK_ON_BOOT    := true
TW_INPUT_BLACKLIST         := "hbtp_vm"
TW_USE_TOOLBOX             := true
TW_INCLUDE_REPACKTOOLS     := true
TW_INCLUDE_RESETPROP       := true
TW_INCLUDE_LIBRESETPROP    := true
TW_INCLUDE_NTFS_3G         := true
TWRP_INCLUDE_LOGCAT        := true
TARGET_USES_LOGD           := true

# Дисплей (1260x2800, density 480)
TW_BRIGHTNESS_PATH         := "/sys/class/backlight/panel0-backlight/brightness"
TW_CUSTOM_CPU_TEMP_PATH    := "/sys/class/thermal/thermal_zone6/temp"
TW_MAX_BRIGHTNESS          := 8191
TW_DEFAULT_BRIGHTNESS      := 2048
TW_NO_SCREEN_BLANK         := true
TW_NO_LOCKSCREEN           := true

# Internal storage = /data/media/0 (UFS, нет физической microSD)
TW_HAS_MTP                 := true
TW_INTERNAL_STORAGE_PATH   := "/data/media/0"
TW_INTERNAL_STORAGE_MOUNT_POINT := "data"
TW_EXTERNAL_STORAGE_PATH   := "/usb_otg"
TW_EXTERNAL_STORAGE_MOUNT_POINT := "usb_otg"

TW_DEVICE_VERSION := 0-Metroid

# Настройки OFRP в /persist (не в зашифрованную data — decrypt невозможен на этом FBE-устройстве)
# Настройки, тема, язык → /persist/Fox/ — переживают ребут
FOX_SETTINGS_ROOT_DIRECTORY := /persist

# === FBE decrypt parameters (see DECRYPT_FINDINGS.md) ===
# Real vendor security patch (empty in recovery otherwise -> KeyMint patchlevel 0)
VENDOR_SECURITY_PATCH := 2026-04-05
# sku selects VINTF manifest_tuna.xml (else NULL VINTF MANIFEST -> KeyMint not declared)
TW_DEFAULT_PROPS += ro.boot.product.vendor.sku=tuna
TW_DEFAULT_PROPS += ro.vendor.build.security_patch=2026-04-05
# NOTE: do NOT set keymaster_ver=4.1 — sends keystore2 to legacy HIDL instead of AIDL KeyMint
