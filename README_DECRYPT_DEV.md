# Metroid FBE Decrypt — Dev Handoff (branch: fbe-decrypt-wip)

This branch integrates the full FBE decrypt stack that reaches the TrustZone wall.
Read **DECRYPT_FINDINGS.md** first — it's the map of what works and where the wall is.

## Before building — DROP IN THE A16 LIBS
The namespace needs A16 libs that aren't in this repo (vendor libs, pull them yourself):

    # from a live A16 system on the device (or A16 system image):
    adb pull /system/lib64/libbinder.so
    adb pull /system/lib64/libbinder_ndk.so
    adb pull /system/lib64/libvndksupport.so
    adb pull /system/lib64/libc++.so
    # libapexsupport.so: from the runtime apex (/apex/com.android.runtime/lib64/ or /system/lib64/)

Place all of them in:  recovery/root/system/lib64_a16/

At boot, of_decrypt_libs.sh copies them into /persist/decrypt_libs (persist is a
separate partition, not ramdisk). The decrypt services load them first via LD_LIBRARY_PATH.

## Build
    source build/envsetup.sh
    lunch twrp_Metroid-userdebug
    mka recoveryimage -j$(nproc)

## What happens on boot
1. of_decrypt_libs.sh copies A16 libs -> /persist/decrypt_libs
2. on encrypted FBE data: chmod dma-heap, mount vendor+odm, start qseecomd
3. qseecomd registers TZ listeners -> starts KeyMint + keystore2
4. KeyMint opens TZ, negotiates shared secret... then HANGS on getRootOfTrust
   (futex_wait) because bootloader is orange. See DECRYPT_FINDINGS.md "The wall".

## Where to focus
The only untested userspace-side lead: Ghidra-patch KeyMint to bypass the init hang
(keymint_get_root_of_trust @0x34550) and reach begin_operation @0x30c64 (the actual
unwrap) to test if the unwrap op has a different boot-stage gate than getRootOfTrust.
Details in DECRYPT_FINDINGS.md. Low odds, but nobody's tested it.

## Note
main branch is the stable SERVICE recovery (no decrypt, stable adb/UI). This branch
turns crypto back on and starts the decrypt chain — expect the UI to hang on splash
when it hits the TZ wall (that's the current end state, by design of the investigation).
