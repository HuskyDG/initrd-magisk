# initrd-magisk
Another simple way to integrate Magisk into Android-x86 project (BlissOS, PrimeOS, ...)


## How to use?

1. In Android-x86 directory (which contain initrd.img, system.img, data, or data.img, ...), rename `initrd.img` to `initrd_real.img` and put `initrd-magisk` as `initrd.img`.
2. Download **magisk apk** and put it as `magisk.apk` in Android-88 directory.

## How does it works?

- System launched with `initrd-magisk.img` unpacked into root directory in first stage, then unpack original `initrd.img` to root directory.
- Extract `magisk.apk` and put binaries into `/magisk`
- Put `99_magisk` script into `/scripts` which is executed to patch `/android` and put magisk binaries into next stage.
- Launch `init` script from original `initrd.img` and continue to boot.
- Execute `99_magisk` script and patch Android's root directory
  - On rootfs, directly add magisk binaries into `/android/magisk` and magisk services into `init.rc`
  - On system-as-root, mount tmpfs on `/android/dev`, mount overlayfs on `/system/etc/init` and add magisk binaries and `magisk.rc`.
  - Patch sepolicy file, dump it into `/android/dev/.overlay/sepolicy` and mount bind into `/sepolicy` or vendor precompiled sepolicy.
  - Unmount `/android/dev`
- `init` switch root to `/android` and execute `/init` to boot into Android.
- Android boot with Magisk


## Build initrd on Linux environment

1. Prepare environment:
```
apt update; apt upgrade
pkg install git
pkg install cpio
```

2. Clone this repo by:

```
git clone http://github.com/huskydg/initrd-magisk
```

3. Change current directory to `~/initrd-magisk`:
```
cd ~/initrd-magisk
```

4. Build with these command:
```
chmod -R 777 *; find * | cpio -o -H newc | gzip > ../initrd-magisk.img
```
