# NP3 (Metroid) FBE Decrypt in Recovery — Findings & Handoff

Device: Nothing Phone 3, codename **Metroid**, SoC SM8735 "sun", device sku **tuna**,
Snapdragon 8s Gen 4. Recovery base: OFRP fox-14.1 (Android 14). Vendor: Android 15.

## TL;DR
The full decrypt stack (`qseecomd -> KeyMint AIDL -> keystore2 -> vold`) can be brought
up on the A14 recovery base against A15 vendor. It reaches a **TrustZone wall**: KeyMint
hangs on its first `getRootOfTrust` TZ transaction because the bootloader is unlocked
(`ro.boot.verifiedbootstate=orange`). No userspace path past it was found. This doc is
the map so you don't re-walk the solved parts and can focus on the wall.

## Device constants
- device sku: `ro.boot.product.vendor.sku=tuna` (NOT sun — sun is the SoC platform, tuna selects the VINTF manifest)
- bootloader: `verifiedbootstate=orange` (unlocked) — the root cause of the wall
- /data: FBE `aes-256-xts:aes-256-cts:v2+inlinecrypt+wrappedkey_v0`, KeyMint AIDL v3, key wrapped by QTEE hardware key
- dma-heap: `/dev/dma_heap/qcom,qseecom{,-ta}` (no /dev/ion, CONFIG_ION unset)
- vendor security_patch (real, from vendor build.prop): `2026-04-05`

## What works (every software blocker solved)

1. **qseecomd linkage** — needs A15 libbinder symbols (`openDeclaredPassthroughHal`)
   absent in A14 recovery libs. Single-lib swaps cascade to libc++ vtable mismatch that
   kills every system binary. FIX: coherent A16 lib set in `/persist/decrypt_libs/`
   (persist mounts early, unencrypted), loaded first via `LD_LIBRARY_PATH`.
   Libs shipped in this branch (recovery/root/system/lib64_a16/): libbinder.so,
   libbinder_ndk.so, libapexsupport.so, libvndksupport.so. NOTE: libc++ is loaded from
   /vendor/lib64/libc++.so (A15) at runtime — the vendor one works, no A16 libc++ needed
   in the persist set. Verified via `linker64 --list` during bring-up.

2. **dma-heap** — "No ion heap of name qcom,qseecom" is NOT ion/SELinux. Recovery ueventd
   makes heap nodes 0600 root:root; OS has 0644 system:system. `chmod 0644` + `chown
   system system` on both -> `vendor.sys.listeners.registered=true`. TZ reachable.

3. **VINTF** — no main manifest.xml (only manifest_{sun,kera,tuna}.xml), and
   /odm/etc/vintf/manifest.xml is a symlink loop (/odm->/vendor/odm->/odm) because odm
   isn't mounted in recovery -> NULL VINTF MANIFEST -> KeyMint never declared. FIX: set
   `ro.boot.product.vendor.sku=tuna` (SM picks manifest_tuna.xml) + mount odm early to
   break the loop. Then SM publishes IKeyMintDevice/default v3, keystore2 waits on it.

4. **keystore2** — completes shared-secret negotiation with KeyMint (TZ responds here).
   Needs /tmp/misc/keystore + keystore.boot_level=0. Do NOT set keymaster_ver=4.1 — it
   sends keystore2 down the legacy HIDL path; it should use AIDL KeyMint by default.

5. **patchlevel** — `ro.vendor.build.security_patch` is EMPTY in recovery (vendor
   build.prop not imported). Real value 2026-04-05. Inject via resetprop OR set
   VENDOR_SECURITY_PATCH build var. Removes "Patchlevel does not match" — but does NOT
   unstick the wall.

## The wall (unsolved — this is where to focus)

With all of the above, `vendor.keymint-qti` starts, opens /dev/smcinvoke (qtee-15),
connects to qseecomd socket, spawns 4 binder threads (alive, wait_woken) — then the main
thread issues its first TZ transaction (getRootOfTrust) and parks in `futex_wait`.
It NEVER returns, so KeyMint never calls registerAsService -> keystore2 waits forever ->
vold blocks -> UI hangs on splash.

- Spoofing `verifiedbootstate=green` + `flash.locked=1` via resetprop: no effect.
  TZ reads its own protected boot state over a hardware channel, not Android props.
- Fixing patchlevel: no effect on the hang.

### Decompilation (Ghidra) — decision is in QTEE, not userspace
`libqtikeymint.so`: `set_device_locked`, `keymint_get_root_of_trust`@0x34550,
`begin_operation`@0x30c64 are all serialize -> send_cmd -> TZ via /dev/qseecom
("Qualcomm QTEE KeyMint 3"). No boot-state check in userspace to patch. The wrapped key
(wrappedkey_v0) is wrapped by a QTEE hardware key bound to the RoT; only the same TZ in
the same state unwraps it. Patching the userspace courier does not change QTEE's decision.

Same boundary the LOS 23 port hit (Status(-8)/EARLY_BOOT_ONLY).

## The one untested lead (~15-20%)
KeyMint hangs on **init/getRootOfTrust**, before reaching the actual unwrap
(begin_operation). A Ghidra patch to bypass the init hang so KeyMint registers and
reaches begin_operation/unwrap would test whether the unwrap op itself is gated by the
same boot-stage — it's a SEPARATE TZ op and MIGHT have different conditions. Low odds
(the gate is likely shared), but nobody has tested it. This is the only userspace-side
vector left. Note: data was re-encrypted after unlock, so the wrapped key is bound to
the CURRENT orange-state RoT — TZ is mathematically capable of unwrapping it; the block
is the boot-stage gate on the operation, not an RoT mismatch.

## Bonus finding (unrelated to decrypt, but bit us)
MTP breaks USB in recovery on this FBE device: composite `mtp,adb` gadget cycles
(connect/disconnect loop, PID d001<->d00d) because MTP can't init without storage access
(data encrypted). Use plain `sys.usb.config=adb` in recovery — drop MTP.
MEOF

echo "DECRYPT_FINDINGS.md создан ($(wc -l < DECRYPT_FINDINGS.md) строк)"
ls -la /home/claude/devpack/